require 'rails_helper'
require 'timeout'

# Prepared native PostgreSQL/Task/audit tests, not yet executed. The direct
# schema fixture is not public editor/API proof. Fault injection is explicit;
# authorization, native writes, receipts and real contention are not mocked.
RSpec.describe 'Independent typed ending execution and actual PostgreSQL contention' do
  self.use_transactional_tests = false

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned disposable typed ending database required' unless owned
    raise 'Committed typed ending fixtures required' if ApplicationRecord.connection.transaction_open?

    example.run
  end

  include_context 'with native typed ending schema evidence'
  include_context 'with native ending attempt operators'

  def queued_typed_attempt
    typed_attempt(consent: typed_consent)
  end

  def execute_typed_attempt(row, source_account = account)
    JrcContactCenter::EndingActions::ExecuteDestinationAttempt.new(account: source_account, attempt_id: row.id).call
  end

  def queued_operator_typed_attempt(operator)
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

  def typed_effect_counts
    [JrcProjects::Task.where(account: account).count,
     JrcProjects::AuditEvent.where(account: account, action: 'projects.task.created').count,
     JrcContactCenter::EndingDestinationExecution.where(account: account).count,
     JrcContactCenter::EndingDestinationOutcome.where(account: account).count]
  end

  def typed_worker(row, state)
    ids = [account.id, row.id]
    Thread.new do
      ApplicationRecord.connection_pool.with_connection do |connection|
        state[:ready] << connection.raw_connection.backend_pid
        command = JrcContactCenter::EndingActions::ExecuteDestinationAttempt.new(account: Account.find(ids.first), attempt_id: ids.last)
        state[:results] << command.call
      end
    rescue StandardError => e
      state[:results] << e
    end
  end

  def wait_for_typed_lock(state)
    pid = Timeout.timeout(8) { state[:ready].pop }
    query = typed_owned_lock_sql(pid)
    Timeout.timeout(8) do
      ApplicationRecord.connection.uncached { sleep 0.02 until ApplicationRecord.connection.select_value(query) == true }
    end
    pid
  end

  def typed_owned_lock_sql(pid)
    # A later contender may wait behind another worker before the owned lock.
    # UNION visits each live blocker once, including when the graph has a cycle.
    <<~SQL.squish
      WITH RECURSIVE blockers(pid) AS (
        SELECT unnest(pg_blocking_pids(#{Integer(pid)}))
        UNION
        SELECT next_blocker.pid FROM blockers
        CROSS JOIN LATERAL unnest(pg_blocking_pids(blockers.pid)) AS next_blocker(pid)
        WHERE blockers.pid <> pg_backend_pid() AND blockers.pid > 0
      )
      SELECT EXISTS (SELECT 1 FROM blockers WHERE pid = pg_backend_pid())
    SQL
  end

  def join_typed_workers(workers)
    workers.each do |worker|
      worker.join(20)
      raise 'Synthetic typed worker remained active' if worker.alive?
    end
  end

  it 'commits one real native Task and audit with its independent typed success and outcome' do
    row = queued_typed_attempt
    result = execute_typed_attempt(row)
    expect(result).to have_attributes(outcome: 'succeeded', result_code: 'completed', attempt_id: row.id)
    expect(result.execution).to have_attributes(target_type: 'JrcProjects::Task', operation: 'create_task',
                                               target_id: JrcProjects::Task.where(account: account).sole.id)
    expect(typed_effect_counts).to eq([1, 1, 1, 1])
    expect(JrcContactCenter::EndingActionExecution.where(account: account)).to be_empty
  end

  it 'acknowledges terminal redelivery without creating or completing another destination' do
    row = queued_typed_attempt
    result = execute_typed_attempt(row)
    expect(execute_typed_attempt(row).attributes).to eq(result.attributes)
    expect(execute_typed_attempt(row).attributes).to eq(result.attributes)
    expect(typed_effect_counts).to eq([1, 1, 1, 1])
  end

  it 'does not find a typed attempt through a different account' do
    row = queued_typed_attempt
    other = create(:account)
    expect { execute_typed_attempt(row, other) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(typed_effect_counts).to eq([0, 0, 0, 0])
  end

  it 'executes as the original non-administrator agent rather than the configuration manager' do
    operator = attempt_operator
    row = queued_operator_typed_attempt(operator)
    result = JrcServiceDesk::NativeExecutionContext.with(account: account, account_user: member, user: actor) do
      execute_typed_attempt(row)
    end
    expect(result.outcome).to eq('succeeded')
    task = JrcProjects::Task.where(account: account).sole
    event = JrcProjects::AuditEvent.where(account: account, action: 'projects.task.created').sole
    expect([row.actor_account_user_id, row.actor_user_id, task.created_by_id, event.actor_id])
      .to eq([operator.id, operator.user_id, operator.user_id, operator.user_id])
    expect(operator.reload.administrator?).to be false
    expect(typed_effect_counts).to eq([1, 1, 1, 1])
  end

  it 'does not borrow an ambient administrators destination access after the original agents access is revoked' do
    operator = attempt_operator
    row = queued_operator_typed_attempt(operator)
    operator.update!(jrc_projects_enabled: false)
    result = JrcServiceDesk::NativeExecutionContext.with(account: account, account_user: member, user: actor) do
      execute_typed_attempt(row)
    end
    expect(result).to have_attributes(outcome: 'blocked', result_code: 'reference_unavailable', execution_id: nil)
    expect(typed_effect_counts).to eq([0, 0, 0, 1])
  end

  it 'requires the original agents current Control Desk eligibility independently of Projects access' do
    operator = attempt_operator
    row = queued_operator_typed_attempt(operator)
    JrcContactCenter::AccessGrant.find_by!(account: account, account_user: operator).update!(eligible: false)
    result = execute_typed_attempt(row)
    expect(result).to have_attributes(outcome: 'blocked', result_code: 'authorization_denied', execution_id: nil)
    expect(operator.reload.jrc_projects_enabled?).to be true
    expect(typed_effect_counts).to eq([0, 0, 0, 1])
  end

  it 'rejects a caller-owned transaction instead of sharing the native effect with unrelated work' do
    row = queued_typed_attempt
    expect do
      ApplicationRecord.transaction { execute_typed_attempt(row) }
    end.to raise_error(JrcContactCenter::OperationError, 'ending_execution_requires_independent_transaction')
    expect(row.reload.outcome).to be_nil
    expect(typed_effect_counts).to eq([0, 0, 0, 0])
  end

  it 'blocks an unfinished attempt under current destination feature permissions' do
    row = queued_typed_attempt
    account.disable_features!('jrc_projects')
    result = execute_typed_attempt(row)
    expect(result).to have_attributes(outcome: 'blocked', result_code: 'reference_unavailable', execution_id: nil)
    expect(typed_effect_counts).to eq([0, 0, 0, 1])
  end

  it 'keeps a previously denied attempt terminal even if the feature is restored' do
    row = queued_typed_attempt
    account.disable_features!('jrc_projects')
    denied = execute_typed_attempt(row)
    account.enable_features!('jrc_projects')
    expect(execute_typed_attempt(row).attributes).to eq(denied.attributes)
    expect(typed_effect_counts).to eq([0, 0, 0, 1])
  end

  it 'preserves a permanent deactivation barrier after the rule is reactivated' do
    row = queued_typed_attempt
    publish_typed_schema_definition('active' => false)
    publish_typed_schema_definition('active' => true)
    result = execute_typed_attempt(row)
    expect(result).to have_attributes(outcome: 'blocked', result_code: 'deactivated', execution_id: nil)
    expect(typed_effect_counts).to eq([0, 0, 0, 1])
  end

  it 'rolls back a real native effect and audit before recording an injected receipt failure' do
    row = queued_typed_attempt
    allow(JrcContactCenter::EndingDestinationExecution).to receive(:create!).and_raise('SYNTHETIC private receipt failure')
    result = execute_typed_attempt(row)
    expect(result).to have_attributes(outcome: 'failed', result_code: 'destination_failure', execution_id: nil)
    expect(result.attributes.values.join(' ')).not_to include('SYNTHETIC', 'private receipt failure')
    expect(typed_effect_counts).to eq([0, 0, 0, 1])
  end

  it 'does not allow the v1 Project executor to acquire the schema-2 native effect' do
    row = queued_typed_attempt
    expect do
      JrcContactCenter::EndingActions::ExecuteProjectTask.new(account: account, origin_id: row.origin_id, rule_code: row.rule_code).call
    end.to raise_error(JrcContactCenter::OperationError, 'ending_action_destination_unavailable')
    expect(typed_effect_counts).to eq([0, 0, 0, 0])
    expect(execute_typed_attempt(row).outcome).to eq('succeeded')
    expect(typed_effect_counts).to eq([1, 1, 1, 1])
  end

  it 'serializes two actual workers and commits only one native Task, audit and terminal outcome' do
    row = queued_typed_attempt
    states = Array.new(2) { { ready: Queue.new, results: Queue.new } }
    workers, pids = [], []
    begin
      account.with_lock do
        ApplicationRecord.connection.select_values('SELECT pid FROM pg_stat_activity')
        observer = ApplicationRecord.connection.raw_connection.backend_pid
        expect(ApplicationRecord.connection.select_value(typed_owned_lock_sql(observer))).to be(false)
        states.each do |state|
          workers << typed_worker(row, state)
          pids << wait_for_typed_lock(state)
        end
      end
    ensure
      join_typed_workers(workers)
    end
    results = states.map { |state| Timeout.timeout(8) { state[:results].pop } }
    expect(results.map(&:class)).to eq([JrcContactCenter::EndingDestinationOutcome] * 2)
    expect(results.map(&:id).uniq.length).to eq(1)
    expect(pids.uniq.length).to eq(2)
    expect(pids).not_to include(ApplicationRecord.connection.raw_connection.backend_pid)
    expect(typed_effect_counts).to eq([1, 1, 1, 1])
  end

  it 'rechecks destination access after actually waiting on the native account authority lock' do
    row = queued_typed_attempt
    state = { ready: Queue.new, results: Queue.new }
    workers = []
    begin
      account.with_lock do
        workers << typed_worker(row, state)
        wait_for_typed_lock(state)
        account.disable_features!('jrc_projects')
      end
    ensure
      join_typed_workers(workers)
    end
    result = Timeout.timeout(8) { state[:results].pop }
    expect(result).to have_attributes(outcome: 'blocked', result_code: 'reference_unavailable')
    expect(typed_effect_counts).to eq([0, 0, 0, 1])
  end

  it 'does not reauthorize a disabled pending rule from its original historical readiness while waiting' do
    row = queued_typed_attempt
    state = { ready: Queue.new, results: Queue.new }
    workers = []
    begin
      account.with_lock do
        workers << typed_worker(row, state)
        wait_for_typed_lock(state)
        publish_typed_schema_definition('active' => false)
      end
    ensure
      join_typed_workers(workers)
    end
    result = Timeout.timeout(8) { state[:results].pop }
    expect(result).to have_attributes(outcome: 'blocked', result_code: 'deactivated')
    expect(typed_effect_counts).to eq([0, 0, 0, 1])
  end
end
