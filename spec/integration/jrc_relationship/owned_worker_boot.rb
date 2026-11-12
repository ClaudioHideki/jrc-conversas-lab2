# Explicit manual integration entrypoint, never loaded by the normal spec glob.
# All network/schema/queue guards precede loading the application.
require 'uri'
require 'webmock'

WebMock.enable!
WebMock.disable_net_connect!
nonce = ENV.fetch('JRC_G_NONCE')
database = ENV.fetch('JRC_G_DATABASE')
queue = ENV.fetch('JRC_G_QUEUE')
mode = ENV.fetch('JRC_G_MODE', 'relationship')
raise 'Unknown owned worker mode' unless %w[relationship approvals master].include?(mode)

raise 'Owned worker environment required' unless ENV.fetch('RAILS_ENV') == 'test' && nonce.match?(/\A[0-9a-f]{12}\z/) &&
                                                 database == "jrc_g_worker_20261106_#{nonce}" && queue == "jrc_g_worker_#{nonce}"
raise 'Owned database URL required' unless URI(ENV.fetch('DATABASE_URL')).path == "/#{database}" && ENV.fetch('POSTGRES_DATABASE') == database

redis_index = mode == 'master' ? 12 : 15
raise 'Owned Redis URL required' unless ENV.fetch('REDIS_URL') == "redis://jrc-rel-v2-redis-20261101:6379/#{redis_index}"

require File.expand_path('../../../config/environment', __dir__)
raise 'Unexpected worker database' unless Rails.env.test? && ActiveRecord::Base.connection.select_value('SELECT current_database()') == database
raise 'Pending worker migrations' if ActiveRecord::Base.connection.migration_context.needs_migration?

Rails.logger.level = Logger::WARN

# Only routing/delivery configuration is changed for this isolated test. The
# native perform/authentication/transaction code remains untouched.
jobs = if mode == 'approvals'
         require_relative 'owned_approval_witness'
         [JrcApprovals::NotificationRecoveryJob, JrcApprovals::NotificationProjectionJob, EventDispatcherJob, ActionCableBroadcastJob]
       else
         [JrcRelationship::BatchExecutionJob]
       end
jobs.each do |job|
  job.queue_adapter = :sidekiq
  job.queue_as queue
end

class JrcOwnedWorkerReceipt
  def initialize(key)
    @key = key
  end

  def call(_worker, job, queue)
    return yield if health_job?(job, queue)

    raise 'Unexpected owned queue payload' unless allowed_payload?(job, queue)

    if ENV['JRC_G_MODE'] == 'master'
      claim = Sidekiq.redis { |redis| redis.call('GET', 'jrc_g_worker_claim') }
      raise 'Owned master Redis lease lost' unless claim == ENV.fetch('JRC_G_NONCE')
    end

    yield
    event_job = %w[EventDispatcherJob ActionCableBroadcastJob].include?(job['wrapped'])
    JrcOwnedApprovalWitness.capture(job, @key) if job['wrapped'] == 'ActionCableBroadcastJob'
    receipt = event_job ? "#{@key}:native_events" : @key
    Sidekiq.redis { |redis| redis.call('SADD', receipt, job.fetch('jid')) }
  end

  def health_job?(job, queue)
    queue == SidekiqAlive.current_queue && job['class'] == 'SidekiqAlive::Worker' && job['args'] == [SidekiqAlive.hostname]
  end

  def allowed_payload?(job, queue)
    allowed = if ENV['JRC_G_MODE'] == 'approvals'
                %w[JrcApprovals::NotificationRecoveryJob JrcApprovals::NotificationProjectionJob EventDispatcherJob ActionCableBroadcastJob]
              else
                ['JrcRelationship::BatchExecutionJob']
              end
    queue == ENV.fetch('JRC_G_QUEUE') && allowed.include?(job['wrapped'])
  end
end

Sidekiq.configure_server do |config|
  config.logger.level = Logger::WARN
  config.on(:startup) do
    raise 'Unexpected consumer queues' unless (config.queues - [queue, SidekiqAlive.current_queue]).empty? && config.queues.include?(queue)
    raise 'Unexpected consumer concurrency' unless config.concurrency == 1

    claim = Sidekiq.redis { |redis| redis.call('GET', 'jrc_g_worker_claim') }
    raise 'Owned Redis claim required' unless claim == nonce

    File.write(ENV.fetch('JRC_G_READY_FILE'), Process.pid.to_s)
  end
  config.server_middleware { |chain| chain.add JrcOwnedWorkerReceipt, ENV.fetch('JRC_G_RECEIPT_KEY') }
  config.on(:shutdown) do
    attempts = WebMock::RequestRegistry.instance.requested_signatures.hash.values.sum
    jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.map { |job| job[:job].name }
    forbidden = jobs.intersect?(%w[Notification::EmailNotificationJob Notification::PushNotificationJob])
    File.write(ENV.fetch('JRC_G_WORKER_NETWORK_FILE'), JSON.generate(attempts: attempts, external_delivery_requested: forbidden))
  end
end
