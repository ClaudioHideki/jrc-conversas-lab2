# Run explicitly with the guarded host helper; not an automatically skipped or
# mocked RSpec case. Data remains in its newly created synthetic-only database.
require 'uri'
require 'webmock'
require 'sidekiq/api'
require 'json'
require_relative 'owned_worker_fixtures'

WebMock.enable!
WebMock.disable_net_connect!

class JrcOwnedWorkerGate
  include JrcOwnedWorkerFixtures
  class Failure < StandardError; end

  def initialize
    @nonce = ENV.fetch('JRC_G_NONCE')
    @database = ENV.fetch('JRC_G_DATABASE')
    @queue = ENV.fetch('JRC_G_QUEUE')
    @receipt_key = ENV.fetch('JRC_G_RECEIPT_KEY')
    @directory = ENV.fetch('JRC_G_DIRECTORY')
    @checks = []
    @phase = 'environment'
  end

  def run
    validate_environment!
    @phase = 'synthetic_records'
    seed!
    @phase = 'worker_boot'
    start_worker!
    exercise!
    @passed = true
  ensure
    begin
      stop_worker!
      @shutdown_clean = true
    ensure
      write_report!
    end
  end

  private

  def exercise!
    @phase = 'committed_native_batch'
    execute_success!
    @phase = 'duplicate_delivery'
    execute_duplicate!
    @phase = 'revoked_authority'
    execute_revoked!
    @phase = 'tenant_and_network'
    check!('foreign account allocation unchanged', @foreign.reload.attributes == @foreign_attributes)
    check!('no HTTP requests attempted', WebMock::RequestRegistry.instance.requested_signatures.hash.empty?)
  end

  def check!(name, result)
    raise Failure, name unless result

    @checks << name
  end

  def validate_environment!
    check!('test environment and exact owned names', Rails.env.test? && @nonce.match?(/\A[0-9a-f]{12}\z/) &&
                                                   @database == "jrc_g_worker_20261106_#{@nonce}" && @queue == "jrc_g_worker_#{@nonce}")
    validate_database!
    validate_redis!
    check!('owned artifact directory', @directory == "/tmp/jrc_g_worker_#{@nonce}" && File.directory?(@directory))
    @validated = true
    Rails.logger.level = Logger::WARN
    JrcRelationship::BatchExecutionJob.queue_adapter = :sidekiq
    JrcRelationship::BatchExecutionJob.queue_as @queue
  end

  def validate_database!
    check!('exact PostgreSQL URL/database', URI(ENV.fetch('DATABASE_URL')).path == "/#{@database}" &&
                                          ActiveRecord::Base.connection.select_value('SELECT current_database()') == @database)
    check!('no pending migrations', !ActiveRecord::Base.connection.migration_context.needs_migration?)
    check!('fresh empty business database', Account.count.zero? && User.count.zero? && JrcRelationship::Assignment.count.zero?)
    check!('committed cross-process fixtures', !ActiveRecord::Base.connection.transaction_open?)
  end

  def validate_redis!
    check!('exact isolated Redis', ENV.fetch('REDIS_URL') == 'redis://jrc-rel-v2-redis-20261101:6379/15' &&
                                  Redis::Config.app.fetch(:url) == ENV.fetch('REDIS_URL'))
    check!('Redis ownership claim', Sidekiq.redis { |redis| redis.call('GET', 'jrc_g_worker_claim') } == @nonce)
  end

  def seed!
    @account = synthetic_account('primary')
    @actor = synthetic_actor(@account, 'success')
    @success, @group, @records = reviewed(@account, @actor, 12, 'successful')
    @originals = @records.map(&:attributes)
    @revoked_actor = synthetic_actor(@account, 'revoked')
    @blocked, @blocked_group, @blocked_records = reviewed(@account, @revoked_actor, 2, 'revoked')
    @blocked_originals = @blocked_records.map(&:attributes)
    @pinned = @blocked.attributes.slice('inputs', 'snapshot', 'digest', 'actor_id', 'account_id')
    foreign_account = synthetic_account('foreign')
    foreign_actor = synthetic_actor(foreign_account, 'foreign')
    @foreign = JrcRelationship::Assignment.create!(account: foreign_account, owner: foreign_actor,
                                                   contact: foreign_account.contacts.create!(name: 'Synthetic foreign preserved contact'))
    @foreign_attributes = @foreign.attributes
    revoke_actor!
  end

  def revoke_actor!
    role = @account.custom_roles.create!(name: 'Synthetic queued authority revoked', permissions: %w[contact_manage jrc_relationship_view])
    @account.account_users.find_by!(user: @revoked_actor).update!(role: :agent, custom_role: role)
  end

  def start_worker!
    boot = Rails.root.join('spec/integration/jrc_relationship/owned_worker_boot.rb').to_s
    @worker_pid = Process.spawn(
      'bundle', 'exec', 'sidekiq', '--environment', 'test', '--require', boot, '--queue', @queue, '--concurrency', '1',
      '--timeout', '10', '--tag', @nonce, out: File.join(@directory, 'worker.log'), err: [:child, :out]
    )
    wait_for('owned worker startup') do
      File.file?(ENV.fetch('JRC_G_READY_FILE')) &&
        Sidekiq::ProcessSet.new.any? { |process| process['pid'] == @worker_pid && process['queues'] == [@queue] }
    end
    check!('worker registered only the owned queue', Sidekiq::ProcessSet.new.any? do |process|
      process['pid'] == @worker_pid && process['queues'] == [@queue]
    end)
  end

  def enqueue(review)
    job = JrcRelationship::BatchExecutionJob.set(queue: @queue).perform_later(review.id)
    check!('real Redis provider job ID', job.provider_job_id.is_a?(String) && !job.provider_job_id.empty?)
    job.provider_job_id
  end

  def acknowledgments
    return unless @validated

    Sidekiq.redis { |redis| redis.call('SCARD', @receipt_key) }
  end

  def wait_for(label)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 75
    until yield
      raise Failure, "#{label} timeout" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      raise Failure, 'owned worker exited before checks completed' if @worker_pid && Process.waitpid(@worker_pid, Process::WNOHANG)

      sleep 0.25
    end
  end

  def execute_success!
    enqueue(@success)
    wait_for('three real native deliveries') { @success.reload.state == 'completed' && acknowledgments == 3 }
    check!('twelve committed native results', @success.items.order(:ordinal).pluck(:state) == ['applied'] * 12 &&
                                           @group.customer_links.where(active: true).count == 12)
    check!('native allocations and owners unchanged', @records.map { |record| record.reload.attributes } == @originals)
    @completed = [@success.attributes, @success.items.order(:ordinal).map(&:attributes), @group.reload.attributes]
  end

  def execute_duplicate!
    enqueue(@success)
    wait_for('duplicate delivery acknowledgment') { acknowledgments == 4 }
    current = [@success.reload.attributes, @success.items.order(:ordinal).map(&:attributes), @group.reload.attributes]
    check!('duplicate delivery has no repeated effect', current == @completed)
  end

  def execute_revoked!
    enqueue(@blocked)
    wait_for('revoked actor delivery') { @blocked.reload.state == 'attention' && acknowledgments == 5 }
    check!('revoked actor pending items stopped', @blocked.items.pluck(:state, :error_code) == [%w[canceled BATCH_AUTHORITY_CHANGED]] * 2)
    check!('revoked actor cannot write customer links', @blocked_group.customer_links.count.zero? &&
                                                     @blocked_records.map { |record| record.reload.attributes } == @blocked_originals)
    check!('revoked review history stays pinned', @blocked.attributes.slice(*@pinned.keys) == @pinned)
    pending_count = Sidekiq::Queue.new(@queue).size
    check!('owned queue drained', pending_count.zero?)
  end

  def stop_worker!
    return unless @worker_pid
    return if Process.waitpid(@worker_pid, Process::WNOHANG)

    # A still-unreaped direct child cannot have been replaced by another PID.
    status = File.read("/proc/#{@worker_pid}/status")
    raise Failure, 'worker is not the owned direct child' unless status.match?(/^PPid:\s+#{Process.pid}$/)

    Process.kill('TERM', @worker_pid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30
    until Process.waitpid(@worker_pid, Process::WNOHANG)
      raise Failure, 'owned worker did not exit gracefully' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.25
    end
    network = JSON.parse(File.read(ENV.fetch('JRC_G_WORKER_NETWORK_FILE')))
    check!('worker made no HTTP requests', network.fetch('attempts').zero?)
  rescue Errno::ECHILD
    @worker_pid = nil
  end

  def write_report!
    data = { status: @passed && @shutdown_clean ? 'passed' : 'failed', phase: @phase, checks: @checks, database: @database, queue: @queue,
             delivery_acknowledgments: acknowledgments, fresh_worker: true, application_build: false, production: false,
             qualification: 'Synthetic-only PostgreSQL; real Redis and Sidekiq. Queue routing overridden only for isolation. ' \
                            'No default queue/cron/deployment/Chrome claim.' }
    if @nonce.match?(/\A[0-9a-f]{12}\z/) && @directory == "/tmp/jrc_g_worker_#{@nonce}" && File.directory?(@directory)
      File.write(File.join(@directory, 'result.json'), JSON.pretty_generate(data))
    end
    puts JSON.generate(data)
  end
end

JrcOwnedWorkerGate.new.run
