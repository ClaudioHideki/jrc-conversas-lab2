# Explicit manual integration entrypoint, never loaded by the normal spec glob.
# All network/schema/queue guards precede loading the application.
require 'uri'
require 'webmock'

WebMock.enable!
WebMock.disable_net_connect!
nonce = ENV.fetch('JRC_G_NONCE')
database = ENV.fetch('JRC_G_DATABASE')
queue = ENV.fetch('JRC_G_QUEUE')
raise 'Owned worker environment required' unless ENV.fetch('RAILS_ENV') == 'test' && nonce.match?(/\A[0-9a-f]{12}\z/) &&
                                                 database == "jrc_g_worker_20261106_#{nonce}" && queue == "jrc_g_worker_#{nonce}"
raise 'Owned database URL required' unless URI(ENV.fetch('DATABASE_URL')).path == "/#{database}" && ENV.fetch('POSTGRES_DATABASE') == database
raise 'Owned Redis URL required' unless ENV.fetch('REDIS_URL') == 'redis://jrc-rel-v2-redis-20261101:6379/15'

require File.expand_path('../../../config/environment', __dir__)
raise 'Unexpected worker database' unless Rails.env.test? && ActiveRecord::Base.connection.select_value('SELECT current_database()') == database
raise 'Pending worker migrations' if ActiveRecord::Base.connection.migration_context.needs_migration?

Rails.logger.level = Logger::WARN

# Only routing/delivery configuration is changed for this isolated test. The
# native perform/authentication/transaction code remains untouched.
JrcRelationship::BatchExecutionJob.queue_adapter = :sidekiq
JrcRelationship::BatchExecutionJob.queue_as queue

class JrcOwnedWorkerReceipt
  def initialize(key)
    @key = key
  end

  def call(_worker, job, queue)
    raise 'Unexpected owned queue payload' unless queue == ENV.fetch('JRC_G_QUEUE') && job['wrapped'] == 'JrcRelationship::BatchExecutionJob'

    yield
    Sidekiq.redis { |redis| redis.call('SADD', @key, job.fetch('jid')) }
  end
end

Sidekiq.configure_server do |config|
  config.logger.level = Logger::WARN
  config.on(:startup) do
    raise 'Unexpected consumer queues' unless config.queues == [queue]
    raise 'Unexpected consumer concurrency' unless config.concurrency == 1

    claim = Sidekiq.redis { |redis| redis.call('GET', 'jrc_g_worker_claim') }
    raise 'Owned Redis claim required' unless claim == nonce

    File.write(ENV.fetch('JRC_G_READY_FILE'), Process.pid.to_s)
  end
  config.server_middleware { |chain| chain.add JrcOwnedWorkerReceipt, ENV.fetch('JRC_G_RECEIPT_KEY') }
  config.on(:shutdown) do
    attempts = WebMock::RequestRegistry.instance.requested_signatures.hash.values.sum
    File.write(ENV.fetch('JRC_G_WORKER_NETWORK_FILE'), JSON.generate(attempts: attempts))
  end
end
