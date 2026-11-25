require 'rails_helper'
require 'timeout'
require 'sidekiq/api'
require 'sidekiq/testing'

# Prepared actual process/Redis/PostgreSQL proof, not yet executed. Technical
# consent fixtures do not stand in for a public editor or manual-confirmation UI.
RSpec.describe 'Actual owned typed Sidekiq execution and original authority' do
  self.use_transactional_tests = false
  include_context 'with native typed ending schema evidence'
  include_context 'with native ending attempt operators'

  let(:broker_nonce) { SecureRandom.hex(12) }
  let(:broker_state) { { nonce: broker_nonce, pid: nil, queue: nil, log: nil } }

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned disposable actual typed broker required' unless owned && !ApplicationRecord.connection.transaction_open?

    previous_adapter = JrcContactCenter::EndingDestinationJob.queue_adapter
    previous_test_adapter = JrcContactCenter::EndingDestinationJob._test_adapter
    previous_queue = JrcContactCenter::EndingDestinationJob.queue_name
    JrcContactCenter::EndingDestinationJob.queue_as "jrc_cc_typed_native_#{broker_nonce}"
    broker_state[:queue] = JrcContactCenter::EndingDestinationJob.new.queue_name
    Sidekiq::Testing.disable! { example.run }
  ensure
    begin
      stop_owned_worker
    ensure
      JrcContactCenter::EndingDestinationJob.queue_name = previous_queue if previous_queue
      if previous_adapter
        JrcContactCenter::EndingDestinationJob.queue_adapter = previous_adapter
        JrcContactCenter::EndingDestinationJob.enable_test_adapter(previous_test_adapter)
      end
    end
  end

  before do
    job = JrcContactCenter::EndingDestinationJob
    job.disable_test_adapter
    job.queue_adapter = :sidekiq
    raise 'Actual owned typed Sidekiq adapter required' unless job.queue_adapter.is_a?(ActiveJob::QueueAdapters::SidekiqAdapter)

    account.update!(custom_attributes: account.custom_attributes.merge('jrc_cc_owned_typed_broker_nonce' => broker_nonce))
  end

  def queued_typed_operator(operator)
    original = completed_attempt_source(operator)
    key = SecureRandom.uuid
    consent = JrcContactCenter::EndingDestinationConsent.create!(
      account: account, origin: original, readiness: typed_readiness, actor_account_user_id: operator.id,
      rule_code: 'SYNTHETIC_ORIGIN_RULE', destination_kind: 'project_task', request_key: key
    ).reload
    JrcContactCenter::EndingDestinationAttempt.create!(
      account: account, origin: original, readiness: typed_readiness, consent: consent,
      rule_code: 'SYNTHETIC_ORIGIN_RULE', destination_kind: 'project_task', request_key: key
    ).reload
  end

  def run_owned_worker
    queue = Sidekiq::Queue.new(broker_state.fetch(:queue))
    ids = queue.map(&:jid)
    raise 'Actual Redis delivery required before worker starts' if ids.empty?

    spawn_owned_worker
    wait_for_real_worker(ids)
  end

  def spawn_owned_worker
    broker_state[:log] = File.open("/tmp/jrc-cc-typed-worker-#{broker_nonce}.private", 'wx')
    options = { chdir: Rails.root.to_s, out: broker_state[:log], err: [:child, :out], pgroup: true }
    environment = { 'RAILS_ENV' => 'test', 'JRC_CC_BROKER_NONCE' => broker_nonce,
                    'JRC_CC_BROKER_QUEUE' => broker_state.fetch(:queue), 'JRC_CC_BROKER_ACCOUNT_ID' => account.id.to_s }
    broker_state[:pid] = Process.spawn(environment, 'bundle', 'exec', 'ruby',
                                       'spec/integration/jrc_contact_center/owned_ending_typed_worker_boot.rb',
                                       '-e', 'test', '-q', broker_state.fetch(:queue), '-c', '2', **options)
  end

  def wait_for_real_worker(ids)
    client = Redis.new(url: ENV.fetch('REDIS_URL'))
    Timeout.timeout(90) do
      loop do
        require_owned_worker_alive!
        raise 'Unexpected retry in owned worker' if Sidekiq::RetrySet.new.any? { |row| row.queue == broker_state.fetch(:queue) }

        rows = client.hgetall("jrc_cc_typed_broker:#{broker_nonce}:acks")
        return rows.values.map { |raw| JSON.parse(raw) } if rows.keys.sort == ids.sort

        sleep 0.1
      end
    end
  end

  def require_owned_worker_alive!
    return unless Process.waitpid(broker_state.fetch(:pid), Process::WNOHANG)

    broker_state[:pid] = nil
    raise 'Owned worker exited before receipts'
  end

  def stop_owned_worker
    pid = broker_state.delete(:pid)
    return unless pid
    return if Process.waitpid(pid, Process::WNOHANG)

    Process.kill('TERM', pid)
    Timeout.timeout(30) { Process.waitpid(pid) }
  ensure
    broker_state[:log]&.close
    preserve_worker_log
  end

  def preserve_worker_log
    source = "/tmp/jrc-cc-typed-worker-#{broker_nonce}.private"
    return unless File.file?(source)

    safe = File.readlines(source).map do |line|
      line.match?(/password|secret|access[ _-]?token|authorization|set-cookie/i) ? "[filtered sensitive worker log line]\n" : line
    end
    File.write("/tmp/call-center-ending-typed-broker-#{broker_nonce}.log", safe.join)
  end

  def verify_worker_receipts(rows, attempt)
    boot = Rails.root.join('spec/integration/jrc_contact_center/owned_ending_typed_worker_boot.rb')
    expected = { 'account_id' => account.id, 'attempt_id' => attempt.id, 'worker_pid' => broker_state.fetch(:pid),
                 'source_sha' => ENV.fetch('GITHUB_SHA'), 'witness_sha256' => Digest::SHA256.file(boot).hexdigest,
                 'database' => 'corporate_gratuity_disposable', 'redis_database' => 15 }
    expect(rows).to all(include(expected))
    verify_worker_postgres_receipts(rows)
  end

  def verify_worker_postgres_receipts(rows)
    backends = rows.map { |row| row.fetch('postgres_backend_pid') }
    expect(backends).to all(be_positive)
    expect(backends).not_to include(ApplicationRecord.connection.raw_connection.backend_pid)
  end

  def preserve_typed_broker_proof(rows, attempt, mode)
    raise 'Owned typed queue not drained' unless Sidekiq::Queue.new(broker_state.fetch(:queue)).size == 0

    if Process.waitpid(broker_state.fetch(:pid), Process::WNOHANG)
      broker_state[:pid] = nil
      raise 'Owned typed worker must remain healthy through verification'
    end
    identity = Sidekiq.redis { |client| client.call('CLIENT', 'INFO') }
    raise 'Unexpected producer Redis database' unless identity.split.include?('db=15')

    proof = typed_broker_identity(rows, attempt, mode).merge(typed_broker_business_observations)
    File.write("/tmp/call-center-ending-typed-broker-#{broker_nonce}.json", JSON.pretty_generate(proof))
  end

  def typed_broker_identity(rows, attempt, mode)
    original = attempt.origin
    { source_sha: ENV.fetch('GITHUB_SHA'), synthetic: true, mode: mode, account_id: account.id, attempt_id: attempt.id,
      qualification_id: original.source_qualification_id, original_account_user_id: original.actor_account_user_id,
      original_user_id: original.actor_user_id, destination_kind: attempt.destination_kind, operation: attempt.operation,
      owned_queue: broker_state.fetch(:queue), worker_pid: broker_state.fetch(:pid), worker_receipts: rows,
      actual_database: ApplicationRecord.connection.current_database, actual_redis_database: 15,
      producer_backend_pid: ApplicationRecord.connection.raw_connection.backend_pid,
      healthy_worker_before_owned_shutdown: true, owned_queue_empty_after_worker: true,
      http_egress_blocked_by_test_boundary: true, public_editor_or_provider_or_whole_Part1_homologation: false }
  end

  def typed_broker_business_observations
    { tasks: JrcProjects::Task.where(account: account).pluck(:id, :created_by_id),
      audits: JrcProjects::AuditEvent.where(account: account, action: 'projects.task.created').count,
      native_successes: JrcContactCenter::EndingDestinationExecution.where(account: account).count,
      outcome_codes: JrcContactCenter::EndingDestinationOutcome.where(account: account).pluck(:outcome, :result_code) }
  end

  it 'consumes duplicate typed deliveries on actual Sidekiq without repeating a native effect or borrowing an admin actor' do
    operator = attempt_operator
    attempt = queued_typed_operator(operator)
    JrcContactCenter::EndingDestinationJob.set(queue: broker_state.fetch(:queue)).perform_later(account.id, attempt.id)
    rows = run_owned_worker
    verify_worker_receipts(rows, attempt)
    expect(rows.length).to be >= 2
    expect(operator.reload.administrator?).to be false
    expect(JrcProjects::Task.where(account: account).sole.created_by_id).to eq(operator.user_id)
    expect(JrcProjects::AuditEvent.where(account: account, action: 'projects.task.created').count).to eq(1)
    expect(JrcContactCenter::EndingDestinationExecution.where(account: account).sole.actor_account_user_id).to eq(operator.id)
    expect(attempt.reload.outcome.outcome).to eq('succeeded')
    preserve_typed_broker_proof(rows, attempt, 'duplicate_delivery')
  end

  it 'rechecks current Project rights after a real typed enqueue and before the owned worker executes' do
    operator = attempt_operator
    attempt = queued_typed_operator(operator)
    JrcProjects::ProjectMember.where(account: account, user_id: operator.user_id).sole.update!(role: 'viewer')
    rows = run_owned_worker
    verify_worker_receipts(rows, attempt)
    expect(JrcProjects::Task.where(account: account)).to be_empty
    expect(JrcContactCenter::EndingDestinationExecution.where(account: account)).to be_empty
    expect(attempt.reload.outcome).to have_attributes(outcome: 'blocked', result_code: 'authorization_denied')
    preserve_typed_broker_proof(rows, attempt, 'revoked_original_permission')
  end

  it 'keeps a real queued typed attempt permanently blocked by deactivation despite subsequent reactivation' do
    attempt = queued_typed_operator(member)
    publish_typed_schema_definition('active' => false)
    publish_typed_schema_definition('active' => true)
    rows = run_owned_worker
    verify_worker_receipts(rows, attempt)
    expect(JrcProjects::Task.where(account: account)).to be_empty
    expect(JrcContactCenter::EndingDestinationExecution.where(account: account)).to be_empty
    expect(attempt.reload.outcome).to have_attributes(outcome: 'blocked', result_code: 'deactivated')
    preserve_typed_broker_proof(rows, attempt, 'deactivated_pending')
  end
end
