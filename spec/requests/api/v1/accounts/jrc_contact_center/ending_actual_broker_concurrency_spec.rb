require 'rails_helper'
require 'timeout'
require 'sidekiq/api'
require 'sidekiq/testing'

# Separate mandatory runner-only command. Fake transport is disabled only inside
# the example so native after-commit delivery really reaches Redis and Sidekiq.
RSpec.describe 'Actual owned Sidekiq ending execution and native authority' do
  self.use_transactional_tests = false

  include_context 'with native ending execution original evidence'
  include_context 'with native ending attempt operators'

  let(:broker_nonce) { SecureRandom.hex(12) }
  let(:broker_state) { { nonce: broker_nonce, pid: nil, queue: nil, log: nil } }

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned disposable actual ending broker required' unless owned && !ApplicationRecord.connection.transaction_open?

    previous_adapter = JrcContactCenter::EndingActionsJob.queue_adapter
    previous_test_adapter = JrcContactCenter::EndingActionsJob._test_adapter
    previous_queue = JrcContactCenter::EndingActionsJob.queue_name
    JrcContactCenter::EndingActionsJob.queue_as "jrc_cc_native_#{broker_nonce}"
    broker_state[:queue] = JrcContactCenter::EndingActionsJob.new.queue_name
    Sidekiq::Testing.disable! { example.run }
  ensure
    begin
      stop_owned_worker
    ensure
      JrcContactCenter::EndingActionsJob.queue_name = previous_queue if previous_queue
      if previous_adapter
        JrcContactCenter::EndingActionsJob.queue_adapter = previous_adapter
        JrcContactCenter::EndingActionsJob.enable_test_adapter(previous_test_adapter)
      end
    end
  end

  before do
    configure_owned_transport
    account.update!(custom_attributes: account.custom_attributes.merge('jrc_cc_owned_broker_nonce' => broker_nonce))
    JrcContactCenter::EndingActions::ActivateRule.new(account: account, member: member, rule_code: 'SYNTHETIC_ORIGIN_RULE',
                                                      request_key: SecureRandom.uuid,
                                                      expected_revision: JrcContactCenter::AcwPolicy.new(account: account).revision).call
  end

  # ActiveJob::TestHelper installs its override in before_setup, after around
  # starts. Opt out only this owned Job after setup; other jobs retain :test.
  def configure_owned_transport
    job = JrcContactCenter::EndingActionsJob
    job.disable_test_adapter
    job.queue_adapter = :sidekiq
    raise 'Actual owned Sidekiq adapter required' unless job.queue_adapter.is_a?(ActiveJob::QueueAdapters::SidekiqAdapter)
  end

  def run_owned_worker
    queue = Sidekiq::Queue.new(broker_state.fetch(:queue))
    ids = queue.map(&:jid)
    raise 'Actual Redis delivery required before worker starts' if ids.empty?

    spawn_owned_worker
    wait_for_real_worker(ids)
  end

  def spawn_owned_worker
    broker_state[:log] = File.open("/tmp/jrc-cc-worker-#{broker_nonce}.private", 'wx')
    options = { chdir: Rails.root.to_s, out: broker_state[:log], err: [:child, :out], pgroup: true }
    environment = { 'RAILS_ENV' => 'test', 'JRC_CC_BROKER_NONCE' => broker_nonce,
                    'JRC_CC_BROKER_QUEUE' => broker_state.fetch(:queue), 'JRC_CC_BROKER_ACCOUNT_ID' => account.id.to_s }
    broker_state[:pid] = Process.spawn(environment, 'bundle', 'exec', 'ruby',
                                       'spec/integration/jrc_contact_center/owned_ending_worker_boot.rb',
                                       '-e', 'test', '-q', broker_state.fetch(:queue), '-c', '2', **options)
  end

  def wait_for_real_worker(ids)
    client = Redis.new(url: ENV.fetch('REDIS_URL'))
    Timeout.timeout(90) do
      loop do
        require_owned_worker_alive!
        raise 'Unexpected retry in owned worker' if Sidekiq::RetrySet.new.any? { |row| row.queue == broker_state.fetch(:queue) }

        rows = client.hgetall("jrc_cc_broker:#{broker_nonce}:acks")
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
    source = "/tmp/jrc-cc-worker-#{broker_nonce}.private"
    return unless File.file?(source)

    safe = File.readlines(source).map do |line|
      line.match?(/password|secret|access[ _-]?token|authorization|set-cookie/i) ? "[filtered sensitive worker log line]\n" : line
    end
    File.write("/tmp/call-center-ending-broker-#{broker_nonce}.log", safe.join)
  end

  def verify_worker_receipts(rows, source)
    boot = Rails.root.join('spec/integration/jrc_contact_center/owned_ending_worker_boot.rb')
    expected = {
      'account_id' => account.id, 'qualification_id' => source.source_qualification_id,
      'worker_pid' => broker_state.fetch(:pid), 'source_sha' => ENV.fetch('GITHUB_SHA'),
      'witness_sha256' => Digest::SHA256.file(boot).hexdigest
    }
    expect(rows).to all(include(expected))
  end

  def preserve_broker_proof(rows, source, mode)
    if Process.waitpid(broker_state.fetch(:pid), Process::WNOHANG)
      broker_state[:pid] = nil
      raise 'Owned worker must remain healthy through verification'
    end

    redis_client = Sidekiq.redis { |client| client.call('CLIENT', 'INFO') }
    redis_database = redis_client.split.find { |field| field.start_with?('db=') }.delete_prefix('db=').to_i
    raise 'Unexpected producer Redis database' unless redis_database == 15

    proof = broker_identity(rows, source, mode).merge(broker_business_observations)
    proof[:actual_database] = ApplicationRecord.connection.current_database
    proof[:actual_redis_database] = redis_database
    File.write("/tmp/call-center-ending-broker-#{broker_nonce}.json", JSON.pretty_generate(proof))
  end

  def broker_identity(rows, source, mode)
    { source_sha: ENV.fetch('GITHUB_SHA'), synthetic: true, mode: mode,
      account_id: account.id, qualification_id: source.source_qualification_id,
      original_account_user_id: source.actor_account_user_id, original_user_id: source.actor_user_id,
      worker_pid: broker_state.fetch(:pid), owned_queue: broker_state.fetch(:queue), worker_receipts: rows,
      healthy_worker_before_owned_shutdown: true, http_egress_blocked_by_test_boundary: true,
      provider_or_whole_Part1_homologation: false }
  end

  def broker_business_observations
    { tasks: JrcProjects::Task.where(account: account).pluck(:id, :created_by_id),
      audits: JrcProjects::AuditEvent.where(account: account, action: 'projects.task.created').count,
      native_successes: JrcContactCenter::EndingActionExecution.where(account: account).count,
      outcome_codes: JrcContactCenter::EndingActionAttemptOutcome.where(account: account).pluck(:outcome, :result_code) }
  end

  it 'consumes duplicate real Redis deliveries under the original agent and creates only one native Task and success' do
    operator = attempt_operator
    original = completed_attempt_source(operator)
    JrcContactCenter::EndingActionsJob.set(queue: broker_state.fetch(:queue)).perform_later(account.id, original.source_qualification_id)
    rows = run_owned_worker
    verify_worker_receipts(rows, original)
    expect(rows.length).to be >= 2
    expect(JrcProjects::Task.where(account: account).sole.created_by_id).to eq(operator.user_id)
    expect(JrcProjects::AuditEvent.where(account: account, action: 'projects.task.created').count).to eq(1)
    expect(JrcContactCenter::EndingActionExecution.where(account: account).sole.actor_account_user_id).to eq(operator.id)
    expect(JrcContactCenter::EndingActionAttemptOutcome.where(account: account).sole.outcome).to eq('succeeded')
    preserve_broker_proof(rows, original, 'duplicate_delivery')
  end

  it 'rechecks original project authority after actual enqueue and retains a refusal without creating a Task' do
    operator = attempt_operator
    original = completed_attempt_source(operator)
    expect(JrcContactCenter::EndingActionAttempt.where(account: account)).to be_empty
    JrcProjects::ProjectMember.where(account: account, user_id: operator.user_id).sole.update!(role: 'viewer')
    rows = run_owned_worker
    verify_worker_receipts(rows, original)
    expect(JrcProjects::Task.where(account: account)).to be_empty
    expect(JrcContactCenter::EndingActionExecution.where(account: account)).to be_empty
    expect(JrcContactCenter::EndingActionAttemptOutcome.where(account: account).sole).to have_attributes(
      outcome: 'blocked', result_code: 'authorization_denied'
    )
    preserve_broker_proof(rows, original, 'revoked_original_permission')
  end

  it 'keeps actual queued pending work blocked after disabling and reactivating the rule before dequeue' do
    complete_origin_qualification
    JrcContactCenter::EndingActions::InitialProjectAttempts.new(account: account, qualification_id: qualification.id).call
    project = JrcProjects::Project.where(account: account).sole
    [false, true].each do |active|
      JrcContactCenter::EndingActions::ConfigureRule.new(account: account, member: member,
                                                         input: origin_rule_document(project).merge('active' => active),
                                                         expected_revision: JrcContactCenter::AcwPolicy.new(account: account).revision).call
    end
    rows = run_owned_worker
    verify_worker_receipts(rows, origin)
    expect(JrcProjects::Task.where(account: account)).to be_empty
    expect(JrcContactCenter::EndingActionExecution.where(account: account)).to be_empty
    expect(JrcContactCenter::EndingActionAttemptOutcome.where(account: account).sole).to have_attributes(
      outcome: 'blocked', result_code: 'deactivated'
    )
    preserve_broker_proof(rows, origin, 'deactivated_pending')
  end
end
