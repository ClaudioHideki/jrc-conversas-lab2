# frozen_string_literal: true

# Called only after SyntheticPauseSeed proves its own disposable runner/database.
# Real native configuration, attendance, completion, Task and outcome writes;
# no provider call, fake successful response or production permission mutation.
class JrcContactCenter::SyntheticEndingAttemptHistorySeed
  def self.call(account:, admin:, queue:)
    new(account: account, admin: admin, queue: queue).call
  end

  def initialize(account:, admin:, queue:)
    @account = account
    @admin = admin
    @queue = queue
  end

  def call
    data = JrcContactCenter::SyntheticEndingAutomationSeed.call(account: @account, admin: @admin, queue: @queue)
    JrcServiceDesk::NativeExecutionContext.with(account: @account, account_user: @admin, user: @admin.user) do
      configure_rule!(data)
      qualification = completed_attendance!
      origin = JrcContactCenter::EndingActionOrigin.find_by!(account: @account, source_qualification_id: qualification.id)
      rows = prepare_attempts!(origin)
      execute_distinct_outcomes!(rows)
      data.merge(call_session_id: qualification.call_session_id.to_s, qualification_id: qualification.id.to_s,
                 history_task_id: JrcProjects::Task.where(account: @account).sole.id.to_s, history_attempt_count: 23)
    end
  end

  private

  def configure_rule!(data)
    rule = history_rule(data)
    policy = JrcContactCenter::AcwPolicy.new(account: @account)
    JrcContactCenter::EndingActions::ConfigureRule.new(account: @account, member: @admin, input: rule, expected_revision: policy.revision).call
    JrcContactCenter::EndingActions::ActivateRule.new(account: @account, member: @admin, rule_code: rule.fetch('code'),
                                                      request_key: SecureRandom.uuid, expected_revision: policy.revision).call
  end

  def history_rule(data)
    scope = JrcContactCenter::EndingActionQueueScope.where(account: @account, source_queue_id: @queue.id).order(revision: :desc).first!
    attributes = { 'title' => 'SYNTHETIC private history task', 'priority' => 'medium',
                   'estimated_minutes' => 0, 'board_column_id' => data.fetch(:automation_column_id) }
    parameters = { 'project_id' => data.fetch(:automation_project_id), 'due_after_days' => nil, 'attributes' => attributes }
    { 'code' => 'SYNTHETIC_HISTORY_RULE', 'name' => 'SYNTHETIC history rule', 'reason_code' => data.fetch(:automation_reason),
      'queue_id' => @queue.id.to_s, 'scope_revision' => scope.integrity_sha256, 'timing' => 'acw_completed',
      'active' => true, 'execution_mode' => 'automatic', 'conditions' => { 'outcome_codes' => [] },
      'actions' => [{ 'kind' => 'project_task', 'parameters' => parameters }] }
  end

  def completed_attendance!
    call = JrcContactCenter::CallSession.create!(account: @account, provider: 'synthetic', correlation_id: SecureRandom.uuid,
                                                 direction: 'inbound', status: 'connected', started_at: Time.current, answered_at: Time.current,
                                                 current_unit: @queue.unit, current_queue: @queue)
    JrcContactCenter::CallLeg.create!(account: @account, call_session: call, account_user: @admin, queue: @queue,
                                      direction: 'inbound', status: 'connected', started_at: call.started_at, answered_at: call.answered_at)
    call.update!(status: 'ended', ended_at: Time.current)
    record = JrcContactCenter::Qualification.find_by!(account: @account, call_session: call, account_user: @admin)
    JrcContactCenter::QualificationManager.new(account: @account, member: @admin).complete!(
      record, { reason_code: 'SYNTHETIC_AUTOMATION', outcome_code: 'completed' }
    )
  end

  def prepare_attempts!(origin)
    rows = JrcContactCenter::EndingActions::InitialProjectAttempts.new(account: @account,
                                                                       qualification_id: origin.source_qualification_id).call
    raise 'Native source scheduling must prepare exactly one attempt' unless rows.length == 1

    22.times do
      rows << JrcContactCenter::EndingActions::QueueProjectAttempt.new(account: @account, origin_id: origin.id,
                                                                       rule_code: 'SYNTHETIC_HISTORY_RULE', request_key: SecureRandom.uuid).call
    end
    rows
  end

  def execute_distinct_outcomes!(rows)
    result = JrcContactCenter::EndingActions::ExecuteAttempt.new(account: @account, attempt_id: rows.first.id).call
    raise 'Native history success required' unless result.outcome == 'succeeded'

    @account.disable_features!('jrc_projects')
    begin
      refused = JrcContactCenter::EndingActions::ExecuteAttempt.new(account: @account, attempt_id: rows.second.id).call
      raise 'Native history bounded refusal required' unless refused.result_code == 'reference_unavailable'
    ensure
      @account.enable_features!('jrc_projects')
    end
    inject_terminal_write_failure!(rows.third)
    outcomes = JrcContactCenter::EndingActionAttemptOutcome.where(account: @account)
    raise 'Exactly three independent terminal native outcomes required' unless outcomes.count == 3
  end

  # Exact synthetic account/attempt only. Real worker and rollback; no fabricated
  # outcome. The earlier native success must remain intact during this failure.
  def inject_terminal_write_failure!(row)
    connection = ApplicationRecord.connection
    predicate = "account_id <> #{Integer(@account.id)} OR attempt_id <> #{Integer(row.id)} OR outcome::text <> 'succeeded'::text"
    name = 'cc_synthetic_history_success_failure'
    connection.add_check_constraint(:jrc_contact_center_ending_action_attempt_outcomes, predicate, name: name)
    begin
      result = JrcContactCenter::EndingActions::ExecuteAttempt.new(account: @account, attempt_id: row.id).call
      raise 'Actual bounded native persistence failure required' unless result.outcome == 'failed' && result.result_code == 'destination_failure'
    ensure
      connection.remove_check_constraint(:jrc_contact_center_ending_action_attempt_outcomes, name: name)
    end
  end
end
