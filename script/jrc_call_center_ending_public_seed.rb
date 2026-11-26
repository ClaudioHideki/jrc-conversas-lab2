# frozen_string_literal: true

# Called only inside the existing owned SyntheticPauseSeed. This introduces no
# production grant, imported call or provider command. The two real operations
# belong to one explicit synthetic agent and one existing native Project.
class JrcContactCenter::SyntheticEndingPublicSeed
  PROJECT_RIGHTS = %w[jrc_projects_project_view jrc_projects_task_create jrc_projects_task_view].freeze

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
    verify_owned_fixture!
    data = JrcContactCenter::SyntheticEndingAutomationSeed.call(account: @account, admin: @admin, queue: @queue)
    JrcServiceDesk::NativeExecutionContext.with(account: @account, account_user: @admin, user: @admin.user) do
      authorize_synthetic_operator!(data)
      configure_rule!(data, 'SYNTHETIC_PUBLIC_MANUAL', 'call_end', 'agent_confirmation')
      configure_rule!(data, 'SYNTHETIC_PUBLIC_AUTOMATIC', 'acw_completed', 'automatic')
      prepare_rules!
      qualification = unconfirmed_attendance!
      install_owned_receipt_failure!
      data.merge(call_session_id: qualification.call_session_id.to_s, qualification_id: qualification.id.to_s,
                 ending_reason_code: data.fetch(:automation_reason), original_operator_user_id: @operator.user_id.to_s,
                 manual_rule_code: 'SYNTHETIC_PUBLIC_MANUAL', automatic_rule_code: 'SYNTHETIC_PUBLIC_AUTOMATIC')
    end
  end

  private

  def verify_owned_fixture!
    verify_disposable_environment!
    raise 'Owned synthetic ending browser fixture required' unless @account.name.start_with?('SYNTHETIC ')
    unless [@admin.account_id, @operator.account_id, @queue.account_id].all? { |id| id == @account.id }
      raise 'Synthetic fixture identities must belong to the same new Account'
    end
    raise 'Do not reuse a populated fixture Account' if JrcContactCenter::CallSession.exists?(account: @account)
  end

  def verify_disposable_environment!
    config = ApplicationRecord.connection_db_config
    owned = ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' && Rails.env.test? &&
            config.configuration_hash[:host] == '127.0.0.1' && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' &&
            ApplicationRecord.connection.current_database == 'jrc_sd_bc_portal_concurrency_20261025_test'
    raise 'Owned synthetic ending browser fixture required' unless owned
  end

  def authorize_synthetic_operator!(data)
    @operator.update!(jrc_projects_enabled: true, jrc_projects_permissions: { 'projects.task.create' => true })
    @operator.custom_role.update!(permissions: (@operator.custom_role.permissions + PROJECT_RIGHTS).uniq)
    project = JrcProjects::Project.where(account: @account).find(data.fetch(:automation_project_id))
    JrcProjects::ProjectMember.create!(account: @account, project: project, user: @operator.user, role: 'member')
    raise 'The original synthetic operator must remain a native agent' unless @operator.agent?
  end

  def configure_rule!(data, code, timing, mode)
    input = private_rule(data, code, timing, mode)
    @account.reload
    revision = JrcContactCenter::AcwPolicy.new(account: @account).revision
    JrcContactCenter::EndingActions::ConfigureRule.new(account: @account, member: @admin, input: input, expected_revision: revision).call
  end

  def private_rule(data, code, timing, mode)
    scope = JrcContactCenter::EndingActionQueueScope.where(account: @account, source_queue_id: @queue.id).order(revision: :desc).first!
    parameters = private_project_parameters(data, code)
    { 'code' => code, 'name' => code, 'reason_code' => data.fetch(:automation_reason), 'queue_id' => @queue.id.to_s,
      'scope_revision' => scope.integrity_sha256, 'timing' => timing, 'active' => true, 'execution_mode' => mode,
      'destination_schema_version' => 2, 'conditions' => { 'outcome_codes' => [] },
      'actions' => [{ 'kind' => 'project_task', 'parameters' => parameters }] }
  end

  def private_project_parameters(data, code)
    { 'project_id' => data.fetch(:automation_project_id), 'due_after_days' => nil, 'attributes' => {
      'title' => "#{code} native task", 'priority' => 'medium', 'estimated_minutes' => 0,
      'board_column_id' => data.fetch(:automation_column_id)
    } }
  end

  def prepare_rules!
    %w[SYNTHETIC_PUBLIC_MANUAL SYNTHETIC_PUBLIC_AUTOMATIC].each do |code|
      @account.reload
      revision = JrcContactCenter::AcwPolicy.new(account: @account).revision
      JrcContactCenter::EndingActions::ActivateRule.new(account: @account, member: @admin, rule_code: code,
                                                       request_key: SecureRandom.uuid, expected_revision: revision).call
    end
  end

  def unconfirmed_attendance!
    call = JrcContactCenter::CallSession.create!(account: @account, provider: 'synthetic', correlation_id: SecureRandom.uuid,
                                                 direction: 'inbound', status: 'connected', started_at: Time.current,
                                                 answered_at: Time.current, current_unit: @queue.unit, current_queue: @queue)
    JrcContactCenter::CallLeg.create!(account: @account, call_session: call, account_user: @operator, queue: @queue,
                                      direction: 'inbound', status: 'connected', started_at: call.started_at, answered_at: call.answered_at)
    call.update!(status: 'ended', ended_at: Time.current)
    row = JrcContactCenter::Qualification.find_by!(account: @account, account_user: @operator, call_session: call)
    origin = JrcContactCenter::EndingActionOrigin.find_by!(account: @account, source_qualification_id: row.id)
    verify_open_attendance!(row, origin)

    row
  end

  def verify_open_attendance!(row, origin)
    unless row.completed_at.nil? && JrcContactCenter::EndingConfirmationState.find(row).nil?
      raise 'Real explicit classification and an open native ACW are required before browser consent'
    end
    raise 'Native original actor mismatch' unless origin.actor_account_user_id == @operator.id
    raise 'No early business effect allowed' if JrcProjects::Task.exists?(account: @account)
  end

  def install_owned_receipt_failure!
    # A real DB failure after the native Task write must roll that Task back.
    # It is scoped to this new synthetic account in the disposable database.
    name = "cc_public_ending_#{Integer(@account.id)}"
    check = "account_id <> #{Integer(@account.id)} OR destination_kind <> 'project_task'"
    ApplicationRecord.connection.add_check_constraint(:jrc_contact_center_ending_destination_executions, check, name: name)
  end
end
