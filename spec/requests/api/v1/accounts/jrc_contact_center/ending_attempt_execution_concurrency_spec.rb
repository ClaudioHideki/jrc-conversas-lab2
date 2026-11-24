require 'rails_helper'
require 'timeout'

# Private next increment. Real Task/Audit/receipt/outcome writes, no mocks of
# destination persistence, authorization or PostgreSQL account locks.
RSpec.describe 'Durable ending attempts and independent native Projects outcomes' do
  self.use_transactional_tests = false

  around do |example|
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'corporate_gratuity_disposable'
    raise 'Owned disposable ending attempt database required' unless owned
    raise 'Committed ending attempt fixtures required' if ApplicationRecord.connection.transaction_open?

    example.run
  end

  include_context 'with native ending execution original evidence'
  include_context 'with native ending attempt operators'

  let(:attempt_key) { SecureRandom.uuid }

  before do
    JrcContactCenter::EndingActions::ActivateRule.new(account: account, member: member, rule_code: 'SYNTHETIC_ORIGIN_RULE',
                                                      request_key: SecureRandom.uuid,
                                                      expected_revision: JrcContactCenter::AcwPolicy.new(account: account).revision).call
  end

  def queue_native_attempt(key = attempt_key, original_id = origin.id)
    JrcContactCenter::EndingActions::QueueProjectAttempt.new(account: account, origin_id: original_id,
                                                             rule_code: 'SYNTHETIC_ORIGIN_RULE', request_key: key).call
  end

  def execute_queued_attempt(row)
    JrcContactCenter::EndingActions::ExecuteAttempt.new(account: account, attempt_id: row.id).call
  end

  def native_attempt_effects
    [JrcProjects::Task.where(account: account).count,
     JrcProjects::AuditEvent.where(account: account, action: 'projects.task.created').count,
     JrcContactCenter::EndingActionExecution.where(account: account).count,
     JrcContactCenter::EndingActionAttemptOutcome.where(account: account).count]
  end

  def revise_attempt_rule(changes)
    project = JrcProjects::Project.where(account: account).sole
    JrcContactCenter::EndingActions::ConfigureRule.new(account: account, member: member,
                                                       input: origin_rule_document(project).merge(changes),
                                                       expected_revision: JrcContactCenter::AcwPolicy.new(account: account).revision).call
  end

  def native_attempt_worker(row, state)
    ids = [account.id, row.id]
    Thread.new do
      ApplicationRecord.connection_pool.with_connection do |connection|
        state[:ready] << connection.raw_connection.backend_pid
        state[:results] << JrcContactCenter::EndingActions::ExecuteAttempt.new(account: Account.find(ids.first), attempt_id: ids.last).call
      end
    rescue StandardError => e
      state[:results] << e
    end
  end

  def wait_for_attempt_lock(state)
    pid = Timeout.timeout(8) { state[:ready].pop }
    sql = "SELECT count(*) FROM pg_stat_activity WHERE pid=#{Integer(pid)} AND wait_event_type='Lock'"
    Timeout.timeout(8) do
      ApplicationRecord.connection.uncached { sleep 0.02 until ApplicationRecord.connection.select_value(sql).to_i == 1 }
    end
  end

  def join_attempt_workers(workers)
    workers.each do |worker|
      worker.join(20)
      raise 'Synthetic attempt worker remained active' if worker.alive?
    end
  end

  it 'persists authorized prospective work without creating a Task, audit, success or outcome' do
    complete_origin_qualification
    row = queue_native_attempt
    expect(row).to have_attributes(account_id: account.id, origin_id: origin.id, version_id: origin.version_id,
                                   actor_account_user_id: member.id, actor_user_id: actor.id, destination_kind: 'project_task')
    expect(row.created_at).to be_present
    expect(row.integrity_sha256).to match(/\A[0-9a-f]{64}\z/)
    expect(native_attempt_effects).to eq([0, 0, 0, 0])
  end

  it 'reuses the same scheduling key only for the exact same immutable source and readiness' do
    complete_origin_qualification
    first = queue_native_attempt
    expect(queue_native_attempt.attributes).to eq(first.attributes)
    expect(JrcContactCenter::EndingActionAttempt.where(account: account).count).to eq(1)
    expect(native_attempt_effects).to eq([0, 0, 0, 0])
  end

  it 'does not queue an unconfirmed or unfinished classification' do
    expect { queue_native_attempt }.to raise_error(JrcContactCenter::OperationError, 'ending_action_trigger_pending')
    expect(JrcContactCenter::EndingActionAttempt.where(account: account)).to be_empty
    expect(native_attempt_effects).to eq([0, 0, 0, 0])
  end

  it 'requires the native destination feature while scheduling as well as during execution' do
    complete_origin_qualification
    account.disable_features!('jrc_projects')
    expect { queue_native_attempt }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcContactCenter::EndingActionAttempt.where(account: account)).to be_empty
  end

  it 'commits one real Task, native audit, immutable success and terminal outcome together' do
    complete_origin_qualification
    row = queue_native_attempt
    result = execute_queued_attempt(row)
    expect(result).to have_attributes(account_id: account.id, attempt_id: row.id, outcome: 'succeeded', result_code: 'completed')
    expect(result.execution.target_id).to eq(JrcProjects::Task.where(account: account).sole.id)
    expect(native_attempt_effects).to eq([1, 1, 1, 1])
  end

  it 'does not execute or append another outcome when the same finished attempt is delivered again' do
    complete_origin_qualification
    row = queue_native_attempt
    first = execute_queued_attempt(row).attributes
    expect(execute_queued_attempt(row).attributes).to eq(first)
    expect(execute_queued_attempt(row).attributes).to eq(first)
    expect(native_attempt_effects).to eq([1, 1, 1, 1])
  end

  it 'retains independent attempt histories while sharing the one atomic success of a duplicated delivery' do
    complete_origin_qualification
    first = queue_native_attempt
    second = queue_native_attempt(SecureRandom.uuid)
    left = execute_queued_attempt(first)
    right = execute_queued_attempt(second)
    expect(left.execution_id).to eq(right.execution_id)
    expect(native_attempt_effects).to eq([1, 1, 1, 2])
    expect([left.attempt_id, right.attempt_id]).to eq([first.id, second.id])
  end

  it 'reconciles unfinished work against an already committed native success without recreating its Task' do
    complete_origin_qualification
    row = queue_native_attempt
    receipt = JrcContactCenter::EndingActions::ExecuteProjectTask.new(account: account, origin_id: origin.id,
                                                                      rule_code: row.rule_code).call
    expect(native_attempt_effects).to eq([1, 1, 1, 0])
    result = execute_queued_attempt(row)
    expect(result.execution_id).to eq(receipt.id)
    expect(native_attempt_effects).to eq([1, 1, 1, 1])
  end

  it 'records a current unavailable destination without creating its Task' do
    complete_origin_qualification
    row = queue_native_attempt
    account.disable_features!('jrc_projects')
    result = execute_queued_attempt(row)
    expect(result).to have_attributes(outcome: 'blocked', result_code: 'reference_unavailable', execution_id: nil)
    expect(native_attempt_effects).to eq([0, 0, 0, 1])
  end

  it 'records the original non-administrator agent and does not borrow the configuration manager identity' do
    operator = attempt_operator
    original = completed_attempt_source(operator)
    row = queue_native_attempt(SecureRandom.uuid, original.id)
    result = JrcServiceDesk::NativeExecutionContext.with(account: account, account_user: member, user: actor) do
      outcome = execute_queued_attempt(row)
      expect(Current.account_user.id).to eq(member.id)
      outcome
    end
    expect(row.actor_account_user_id).to eq(operator.id)
    expect(result.execution.actor_account_user_id).to eq(operator.id)
    expect(JrcProjects::Task.where(account: account).sole.created_by_id).to eq(operator.user_id)
    expect(native_attempt_effects).to eq([1, 1, 1, 1])
  end

  it 'blocks an original non-administrator agent changed to viewer after the attempt was queued' do
    operator = attempt_operator
    original = completed_attempt_source(operator)
    row = queue_native_attempt(SecureRandom.uuid, original.id)
    JrcProjects::ProjectMember.where(account: account, user_id: operator.user_id).sole.update!(role: 'viewer')
    result = JrcServiceDesk::NativeExecutionContext.with(account: account, account_user: member, user: actor) do
      execute_queued_attempt(row)
    end
    expect(result).to have_attributes(outcome: 'blocked', result_code: 'authorization_denied', execution_id: nil)
    expect(native_attempt_effects).to eq([0, 0, 0, 1])
  end

  it 'blocks old pending work permanently after disabling and reactivating the rule' do
    complete_origin_qualification
    row = queue_native_attempt
    revise_attempt_rule('active' => false)
    revise_attempt_rule('active' => true)
    result = execute_queued_attempt(row)
    expect(result).to have_attributes(outcome: 'blocked', result_code: 'deactivated', execution_id: nil)
    expect(execute_queued_attempt(row).attributes).to eq(result.attributes)
    expect(native_attempt_effects).to eq([0, 0, 0, 1])
    expect { queue_native_attempt(SecureRandom.uuid) }.to raise_error(JrcContactCenter::OperationError, 'ending_action_pending_permanently_blocked')
  end

  it 'preserves successful history when a later rule revision is deactivated' do
    complete_origin_qualification
    row = queue_native_attempt
    before = execute_queued_attempt(row).attributes
    revise_attempt_rule('active' => false)
    expect(execute_queued_attempt(row).attributes).to eq(before)
    expect(native_attempt_effects).to eq([1, 1, 1, 1])
  end

  it 'rolls the actual Task and success back if terminal success persistence fails, retaining a bounded failure' do
    complete_origin_qualification
    row = queue_native_attempt
    connection = ApplicationRecord.connection
    connection.add_check_constraint(:jrc_contact_center_ending_action_attempt_outcomes,
                                    "outcome::text <> 'succeeded'::text", name: 'cc_synthetic_attempt_success_failure')
    begin
      result = execute_queued_attempt(row)
      expect(result).to have_attributes(outcome: 'failed', result_code: 'destination_failure', execution_id: nil)
      expect(native_attempt_effects).to eq([0, 0, 0, 1])
    ensure
      connection.remove_check_constraint(:jrc_contact_center_ending_action_attempt_outcomes, name: 'cc_synthetic_attempt_success_failure')
    end
    retry_row = queue_native_attempt(SecureRandom.uuid)
    expect(execute_queued_attempt(retry_row).outcome).to eq('succeeded')
    expect(native_attempt_effects).to eq([1, 1, 1, 2])
    expect(row.reload.outcome.outcome).to eq('failed')
  end

  it 'does not accept a known attempt ID from another account' do
    complete_origin_qualification
    row = queue_native_attempt
    other = create(:account)
    expect do
      JrcContactCenter::EndingActions::ExecuteAttempt.new(account: other, attempt_id: row.id).call
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect(native_attempt_effects).to eq([0, 0, 0, 0])
  end

  it 'rejects cross-account source and readiness references at the actual PostgreSQL attempt guard' do
    complete_origin_qualification
    row = queue_native_attempt
    other = create(:account)
    expect do
      JrcContactCenter::EndingActionAttempt.create!(account: other, origin: origin, readiness: row.readiness,
                                                    rule_code: row.rule_code, destination_kind: 'project_task', request_key: SecureRandom.uuid)
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(JrcContactCenter::EndingActionAttempt.where(account: other)).to be_empty
    expect(native_attempt_effects).to eq([0, 0, 0, 0])
  end

  it 'rejects caller-supplied original actor and version evidence at the actual PostgreSQL guard' do
    complete_origin_qualification
    row = queue_native_attempt
    expect do
      JrcContactCenter::EndingActionAttempt.create!(account: account, origin: origin, readiness: row.readiness,
                                                    rule_code: row.rule_code, destination_kind: 'project_task', request_key: SecureRandom.uuid,
                                                    actor_user_id: actor.id, version_id: origin.version_id)
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(JrcContactCenter::EndingActionAttempt.where(account: account).count).to eq(1)
    expect(native_attempt_effects).to eq([0, 0, 0, 0])
  end

  it 'refuses an actual success receipt belonging to another original source in the same account' do
    complete_origin_qualification
    first = queue_native_attempt
    second_source = completed_attempt_source(member)
    second = queue_native_attempt(SecureRandom.uuid, second_source.id)
    legitimate = execute_queued_attempt(second)
    expect do
      JrcContactCenter::EndingActionAttemptOutcome.create!(account: account, attempt: first, execution: legitimate.execution,
                                                           outcome: 'succeeded', result_code: 'completed')
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(first.reload.outcome).to be_nil
    expect(native_attempt_effects).to eq([1, 1, 1, 1])
    expect(execute_queued_attempt(first).outcome).to eq('succeeded')
    expect(native_attempt_effects).to eq([2, 2, 2, 2])
  end

  it 'keeps terminal outcomes immutable even when bypassing ActiveRecord callbacks' do
    complete_origin_qualification
    row = queue_native_attempt
    result = execute_queued_attempt(row)
    expect do
      sql = ['UPDATE jrc_contact_center_ending_action_attempt_outcomes SET result_code=? WHERE account_id=? AND id=?',
             'destination_failure', account.id, result.id]
      ApplicationRecord.connection.execute(ApplicationRecord.sanitize_sql_array(sql))
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect { result.delete }.to raise_error(ActiveRecord::StatementInvalid)
    expect(result.reload.outcome).to eq('succeeded')
    expect(native_attempt_effects).to eq([1, 1, 1, 1])
  end

  it 'keeps the scheduling source immutable even when bypassing ActiveRecord callbacks' do
    complete_origin_qualification
    row = queue_native_attempt
    expect do
      sql = ['UPDATE jrc_contact_center_ending_action_attempts SET rule_code=? WHERE account_id=? AND id=?',
             'SYNTHETIC altered rule', account.id, row.id]
      ApplicationRecord.connection.execute(ApplicationRecord.sanitize_sql_array(sql))
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect { row.delete }.to raise_error(ActiveRecord::StatementInvalid)
    expect(row.reload.rule_code).to eq('SYNTHETIC_ORIGIN_RULE')
    expect(native_attempt_effects).to eq([0, 0, 0, 0])
  end

  it 'serializes two actual workers and appends only one success outcome for the same attempt' do
    complete_origin_qualification
    row = queue_native_attempt
    states = Array.new(2) { { ready: Queue.new, results: Queue.new } }
    workers = []
    begin
      account.with_lock do
        states.each do |state|
          workers << native_attempt_worker(row, state)
          wait_for_attempt_lock(state)
        end
      end
    ensure
      join_attempt_workers(workers)
    end
    results = states.map { |state| Timeout.timeout(8) { state[:results].pop } }
    expect(results.map(&:class)).to eq([JrcContactCenter::EndingActionAttemptOutcome] * 2)
    expect(results.map(&:id).uniq.length).to eq(1)
    expect(native_attempt_effects).to eq([1, 1, 1, 1])
  end

  it 'rechecks a feature revoked while the real worker waits on the native account lock' do
    complete_origin_qualification
    row = queue_native_attempt
    state = { ready: Queue.new, results: Queue.new }
    workers = []
    begin
      account.with_lock do
        workers << native_attempt_worker(row, state)
        wait_for_attempt_lock(state)
        account.disable_features!('jrc_projects')
      end
    ensure
      join_attempt_workers(workers)
    end
    result = Timeout.timeout(8) { state[:results].pop }
    expect(result).to have_attributes(outcome: 'blocked', result_code: 'reference_unavailable')
    expect(native_attempt_effects).to eq([0, 0, 0, 1])
  end
end
