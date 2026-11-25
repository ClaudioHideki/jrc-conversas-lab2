# frozen_string_literal: true

# Called only by the already guarded SyntheticPauseSeed in its owned runner.
# Explicit synthetic permissions; never production grants or provider commands.
class JrcContactCenter::SyntheticEndingPendingSeed
  OPERATOR_PROJECT_RIGHTS = %w[jrc_projects_project_view jrc_projects_task_create jrc_projects_task_view].freeze

  def self.call(account:, admin:, operator:, queue:)
    new(account: account, admin: admin, operator: operator, queue: queue).call
  end

  def initialize(account:, admin:, operator:, queue:)
    @account = account
    @admin = admin
    @operator = operator
    @queue = queue
  end

  def call
    data = JrcContactCenter::SyntheticEndingAutomationSeed.call(account: @account, admin: @admin, queue: @queue)
    JrcServiceDesk::NativeExecutionContext.with(account: @account, account_user: @admin, user: @admin.user) do
      authorize_synthetic_operator!(data)
      %w[SYNTHETIC_SELECTED_PENDING SYNTHETIC_UNSELECTED_PENDING].each { |code| configure_rule!(data, code) }
      qualification = completed_attendance!
      rows = JrcContactCenter::EndingActions::InitialProjectAttempts.new(account: @account, qualification_id: qualification.id).call
      raise 'Exactly two genuinely pending native attempts required' unless rows.length == 2 && rows.none?(&:outcome)
      raise 'Pending fixture must not already contain a native success or task' if JrcProjects::Task.where(account: @account).exists?

      selected = rows.find { |row| row.rule_code == 'SYNTHETIC_SELECTED_PENDING' }
      data.merge(call_session_id: qualification.call_session_id.to_s, qualification_id: qualification.id.to_s,
                 selected_attempt_id: selected.id.to_s, selected_version_id: selected.version_id.to_s,
                 selected_request_id: selected.request_key, original_operator_user_id: @operator.user_id.to_s)
    end
  end

  private

  def authorize_synthetic_operator!(data)
    @operator.update!(jrc_projects_enabled: true, jrc_projects_permissions: { 'projects.task.create' => true })
    @operator.custom_role.update!(permissions: (@operator.custom_role.permissions + OPERATOR_PROJECT_RIGHTS).uniq)
    project = JrcProjects::Project.where(account: @account).find(data.fetch(:automation_project_id))
    JrcProjects::ProjectMember.create!(account: @account, project: project, user: @operator.user, role: 'member')
    raise 'Synthetic original actor must remain a nonadministrator' unless @operator.agent?
  end

  def configure_rule!(data, code)
    rule = rule_document(data, code)
    policy = JrcContactCenter::AcwPolicy.new(account: @account)
    JrcContactCenter::EndingActions::ConfigureRule.new(account: @account, member: @admin, input: rule, expected_revision: policy.revision).call
    JrcContactCenter::EndingActions::ActivateRule.new(account: @account, member: @admin, rule_code: code,
                                                      request_key: SecureRandom.uuid, expected_revision: policy.revision).call
  end

  def rule_document(data, code)
    scope = JrcContactCenter::EndingActionQueueScope.where(account: @account, source_queue_id: @queue.id).order(revision: :desc).first!
    attributes = { 'title' => "#{code} native task", 'priority' => 'medium', 'estimated_minutes' => 0,
                   'board_column_id' => data.fetch(:automation_column_id) }
    parameters = { 'project_id' => data.fetch(:automation_project_id), 'due_after_days' => nil, 'attributes' => attributes }
    { 'code' => code, 'name' => code, 'reason_code' => data.fetch(:automation_reason), 'queue_id' => @queue.id.to_s,
      'scope_revision' => scope.integrity_sha256, 'timing' => 'acw_completed', 'active' => true, 'execution_mode' => 'automatic',
      'conditions' => { 'outcome_codes' => [] }, 'actions' => [{ 'kind' => 'project_task', 'parameters' => parameters }] }
  end

  def completed_attendance!
    call = JrcContactCenter::CallSession.create!(account: @account, provider: 'synthetic', correlation_id: SecureRandom.uuid,
                                                 direction: 'inbound', status: 'connected', started_at: Time.current, answered_at: Time.current,
                                                 current_unit: @queue.unit, current_queue: @queue)
    JrcContactCenter::CallLeg.create!(account: @account, call_session: call, account_user: @operator, queue: @queue,
                                      direction: 'inbound', status: 'connected', started_at: call.started_at, answered_at: call.answered_at)
    call.update!(status: 'ended', ended_at: Time.current)
    row = JrcContactCenter::Qualification.find_by!(account: @account, call_session: call, account_user: @operator)
    JrcContactCenter::QualificationManager.new(account: @account, member: @operator).complete!(
      row, { reason_code: 'SYNTHETIC_AUTOMATION', outcome_code: 'completed' }
    )
  end
end
