require 'rails_helper'
require 'timeout'

RSpec.describe 'Selected pending Project execution under actual PostgreSQL contention' do
  self.use_transactional_tests = false

  include_context 'with native ending execution original evidence'
  include_context 'with native ending attempt operators'

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned disposable selected pending concurrency database required' unless owned
    raise 'Committed selected pending fixtures required' if ApplicationRecord.connection.transaction_open?

    example.run
  end

  before do
    JrcContactCenter::EndingActions::ActivateRule.new(
      account: account, member: member, rule_code: 'SYNTHETIC_ORIGIN_RULE', request_key: SecureRandom.uuid,
      expected_revision: JrcContactCenter::AcwPolicy.new(account: account).revision
    ).call
  end

  def selected_pending_fixture
    operator = attempt_operator
    origin = completed_attempt_source(operator)
    row = JrcContactCenter::EndingActions::QueueProjectAttempt.new(
      account: account, origin_id: origin.id, rule_code: 'SYNTHETIC_ORIGIN_RULE', request_key: SecureRandom.uuid
    ).call
    [operator, origin, row]
  end

  def selected_pending_worker(fixture, state)
    operator, origin, row = fixture
    ids = [account.id, operator.id, origin.source_qualification_id, row.id]
    review = { 'confirmed' => true, 'expected_request_key' => row.request_key, 'expected_version_id' => row.version_id.to_s }
    Thread.new do
      ApplicationRecord.connection_pool.with_connection do |connection|
        state[:ready] << connection.raw_connection.backend_pid
        state[:result] << run_selected_command(ids, review)
      end
    rescue StandardError => e
      state[:result] << e
    end
  end

  def run_selected_command(ids, review)
    JrcContactCenter::EndingActions::RunPendingProjectAttempt.new(
      account: Account.find(ids[0]), member: AccountUser.find(ids[1]), qualification_id: ids[2], attempt_id: ids[3], review: review
    ).call
  end

  def wait_for_selected_lock(state)
    pid = Timeout.timeout(8) { state[:ready].pop }
    sql = "SELECT count(*) FROM pg_stat_activity WHERE pid=#{Integer(pid)} AND wait_event_type='Lock'"
    Timeout.timeout(8) do
      ApplicationRecord.connection.uncached { sleep 0.02 until ApplicationRecord.connection.select_value(sql).to_i == 1 }
    end
    pid
  end

  def selected_effects
    [JrcProjects::Task.where(account: account).count,
     JrcProjects::AuditEvent.where(account: account, action: 'projects.task.created').count,
     JrcContactCenter::EndingActionExecution.where(account: account).count,
     JrcContactCenter::EndingActionAttemptOutcome.where(account: account).count]
  end

  def join_selected_workers(workers)
    workers.each do |worker|
      worker.join(20)
      raise 'Synthetic selected pending worker remained active' if worker.alive?
    end
  end

  it 'serializes two actual independent connection requests without duplicating the selected native effect' do
    fixture = selected_pending_fixture
    state = { ready: Queue.new, result: Queue.new }
    workers = []
    pids = []
    account.with_lock do
      workers = Array.new(2) { selected_pending_worker(fixture, state) }
      pids = Array.new(2) { wait_for_selected_lock(state) }
    end
    results = Array.new(2) { Timeout.timeout(20) { state[:result].pop } }
    successes = results.select { |result| result.is_a?(Hash) }
    refusals = results.reject { |result| result.is_a?(Hash) }
    expect(pids.uniq.size).to eq(2)
    expect(successes).not_to be_empty
    expect(successes).to all(include(outcome: 'succeeded', result_code: 'completed', attempt_id: fixture.last.id.to_s))
    expect(refusals.map { |error| [error.class.name, error.respond_to?(:code) && error.code] })
      .to all(eq(['JrcContactCenter::OperationError', 'ending_attempt_no_longer_pending']))
    expect(selected_effects).to eq([1, 1, 1, 1])
    expect(JrcProjects::Task.where(account: account).sole.created_by_id).to eq(fixture.first.user_id)
    expect(JrcContactCenter::EndingActionAttempt.where(account: account).count).to eq(1)
  ensure
    join_selected_workers(workers || [])
  end

  it 'revalidates a native Project role revoked while the selected command is actually blocked on the account mutex' do
    fixture = selected_pending_fixture
    state = { ready: Queue.new, result: Queue.new }
    workers = []
    account.with_lock do
      workers << selected_pending_worker(fixture, state)
      wait_for_selected_lock(state)
      JrcProjects::ProjectMember.where(account: account, user_id: fixture.first.user_id).sole.update!(role: 'viewer')
    end
    result = Timeout.timeout(20) { state[:result].pop }
    expect(result.class.name).to eq('Pundit::NotAuthorizedError')
    expect(selected_effects).to eq([0, 0, 0, 0])
    expect(fixture.last.reload.outcome).to be_nil
  ensure
    join_selected_workers(workers || [])
  end

  it 'does not revive a pending command after a real concurrent disable and reactivation of its rule' do
    fixture = selected_pending_fixture
    previous = fixture.last.attributes
    state = { ready: Queue.new, result: Queue.new }
    workers = []
    account.with_lock do
      workers << selected_pending_worker(fixture, state)
      wait_for_selected_lock(state)
      project = JrcProjects::Project.where(account: account).sole
      [false, true].each do |active|
        JrcContactCenter::EndingActions::ConfigureRule.new(
          account: account, member: member, input: origin_rule_document(project).merge('active' => active),
          expected_revision: JrcContactCenter::AcwPolicy.new(account: account).revision
        ).call
      end
    end
    result = Timeout.timeout(20) { state[:result].pop }
    expect([result.class.name, result.respond_to?(:code) && result.code])
      .to eq(['JrcContactCenter::OperationError', 'ending_action_pending_permanently_blocked'])
    expect(selected_effects).to eq([0, 0, 0, 0])
    expect(fixture.last.reload.attributes).to eq(previous)
    expect(fixture.last.outcome).to be_nil
  ensure
    join_selected_workers(workers || [])
  end
end
