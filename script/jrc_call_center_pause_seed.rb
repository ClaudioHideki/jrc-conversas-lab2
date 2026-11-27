require_relative 'jrc_call_center_operational_form_seed'
require_relative 'jrc_call_center_state_history_seed'
require_relative 'jrc_call_center_ending_reason_seed'
require_relative 'jrc_call_center_ending_confirmation_seed'
require_relative 'jrc_call_center_ending_automation_seed'
require_relative 'jrc_call_center_ending_attempt_history_seed'
require_relative 'jrc_call_center_ending_pending_seed'
require_relative 'jrc_call_center_ending_public_seed'
require_relative 'jrc_call_center_ending_service_desk_seed'
require_relative 'jrc_call_center_recordings_seed'
require_relative 'jrc_call_center_audio_folder_seed'
require_relative 'jrc_call_center_team_supervision_seed'
require_relative 'jrc_call_center_pause_approval_seed'

# Exclusive synthetic accounts; no channels, inboxes or PABX configuration.
class JrcContactCenter::SyntheticPauseSeed
  PENDING_ACW_PROJECTS = %w[
    -acw_draft -acw_review -acw_navigation -deferred_pause -deferred_pause_retry -operational_forms -form_bindings -hoya_forms -approval
  ].freeze

  SCENARIOS = %w[
    editor operations withdrawal duration acw routing state_history
    team_withdrawal team_activity acw_draft acw_review acw_navigation team_deletion deferred_pause deferred_pause_retry
    operational_forms form_bindings hoya_forms required_endings ending_confirmation membership_eligibility audio_folders team_supervision approval
    ending_automations ending_activation ending_history ending_pending ending_operational ending_service_desk recordings
  ].freeze

  def self.call(projects:, scenarios: SCENARIOS)
    config = ActiveRecord::Base.connection_db_config
    owned = [
      ENV['GITHUB_ACTIONS'] == 'true', ENV['RUNNER_ENVIRONMENT'] == 'github-hosted', Rails.env.test?,
      JrcContactCenter::SyntheticRecordingsSeed.owned_database?(config), config.configuration_hash[:host] == '127.0.0.1',
      ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15'
    ].all?
    raise 'Owned synthetic pause runner required' unless owned
    raise 'Unknown synthetic scenarios' unless JrcContactCenter::SyntheticRecordingsSeed.allowed_scenarios?(scenarios, SCENARIOS)

    projects.index_with do |project|
      scenarios.index_with do |kind|
        new("#{project}-#{kind}").call
      end
    end
  end
  private_class_method :new

  def initialize(project)
    @project = project
    @account = Account.create!(name: "SYNTHETIC pause #{project}", locale: 'pt_BR')
    @account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
    @account.enable_features!('team_management') if @project.end_with?('-team_deletion')
  end

  def call
    company = @account.master_companies.create!(name: 'SYNTHETIC pause issuer', relationship_type: 'internal')
    units = create_units(company)
    admin = create_member(
      'administrator', JrcContactCenter::ModulePolicy::PERMISSIONS, :administrator, custom: !@project.end_with?('-team_deletion')
    )
    scoped = create_member('scoped', JrcContactCenter::ModulePolicy::PERMISSIONS, :administrator)
    operator = create_member('operator', %w[jrc_contact_center_view jrc_contact_center_operate], :agent)
    assign_corporate_access(company, units, admin, scoped, operator)
    queues = create_queues(units, operator)
    payload = session_payload(units, queues, admin, scoped, operator)
    if @project.end_with?('-state_history')
      payload.merge!(JrcContactCenter::SyntheticStateHistorySeed.call(account: @account, member: operator, queues: queues))
    end
    if @project.end_with?('-audio_folders')
      payload.merge!(JrcContactCenter::SyntheticAudioFolderSeed.call(account: @account, queues: queues, member: admin))
    end
    prepare_recordings(payload, queues, operator, scoped)
    prepare_pause_sources(payload, queues, admin, operator)
    payload
  end

  private

  def prepare_recordings(payload, queues, operator, viewer)
    return unless @project.end_with?('-recordings')

    payload.merge!(JrcContactCenter::SyntheticRecordingsSeed.call(account: @account, operator: operator, viewer: viewer, queues: queues))
  end

  def prepare_pause_sources(payload, queues, admin, operator)
    prepare_selected_ending_sources(payload, queues.first, admin, operator)
    prepare_service_desk_source(payload, queues.first, admin)
    if @project.end_with?('-ending_history')
      payload.merge!(JrcContactCenter::SyntheticEndingAttemptHistorySeed.call(account: @account, admin: admin, queue: queues.first))
    end
    if @project.end_with?('-ending_automations', '-ending_activation')
      payload.merge!(JrcContactCenter::SyntheticEndingAutomationSeed.call(account: @account, admin: admin, queue: queues.first))
    end
    if @project.end_with?('-ending_confirmation')
      payload.merge!(JrcContactCenter::SyntheticEndingConfirmationSeed.call(account: @account, admin: admin, operator: operator, queue: queues.first))
    end
    prepare_special_sources(payload, queues.first, admin, operator)
    if @project.end_with?('-approval')
      payload.merge!(JrcContactCenter::SyntheticPauseApprovalSeed.call(account: @account, admin: admin, operator: operator, queues: queues))
    end
    payload.merge!(pending_qualification(queues.first, operator)) if @project.end_with?(*PENDING_ACW_PROJECTS)
  end

  def prepare_service_desk_source(payload, queue, admin)
    return unless @project.end_with?('-ending_service_desk')

    payload.merge!(JrcContactCenter::SyntheticEndingServiceDeskSeed.call(account: @account, admin: admin, queue: queue))
  end

  def prepare_selected_ending_sources(payload, queue, admin, operator)
    if @project.end_with?('-ending_operational')
      payload.merge!(JrcContactCenter::SyntheticEndingPublicSeed.call(account: @account, admin: admin, operator: operator, queue: queue))
    end
    return unless @project.end_with?('-ending_pending')

    payload.merge!(JrcContactCenter::SyntheticEndingPendingSeed.call(account: @account, admin: admin, operator: operator, queue: queue))
  end

  def prepare_special_sources(payload, queue, admin, operator)
    if @project.end_with?('-team_supervision')
      payload.merge!(JrcContactCenter::SyntheticTeamSupervisionSeed.call(account: @account, unit: queue.unit))
    end
    payload.merge!(team_source(operator)) if @project.end_with?('-team_withdrawal', '-team_activity')
    if @project.end_with?('-team_deletion')
      JrcContactCenter::AccessGrant.find_by!(account: @account, account_user: admin).update!(allowed: ['jrc_contact_center_audit'])
      payload.merge!(team_source(operator, corporate: false))
    end
    if @project.end_with?('-required_endings')
      payload.merge!(JrcContactCenter::SyntheticEndingReasonSeed.new(account: @account, admin: admin, operator: operator, queue: queue).call)
    end
    prepare_inactive_membership(payload, queue, operator) if @project.end_with?('-membership_eligibility')
    return unless @project.end_with?('-operational_forms', '-form_bindings', '-hoya_forms')

    payload.merge!(JrcContactCenter::SyntheticOperationalFormSeed.new(account: @account, admin: admin, queue: queue).call)
  end

  def prepare_inactive_membership(payload, queue, operator)
    target = JrcContactCenter::Queue.create!(account: @account, unit: queue.unit, code: 'SYNTHETIC-ENROLLMENT',
                                             name: 'SYNTHETIC new enrollment queue')
    membership = queue.memberships.find_by!(account_user: operator)
    operator.user.update!(confirmed_at: nil)
    raise 'Synthetic recipient must not be active for authentication' if operator.user.reload.active_for_authentication?

    payload.merge!(enrollment_queue_id: target.id, inactive_membership_id: membership.id, inactive_user_id: operator.user_id)
  end

  def pending_qualification(queue, operator)
    policy = JrcContactCenter::AcwPolicy.new(account: @account)
    rules = [{ id: 'synthetic-order', reason_code: 'order', scope: 'queue', scope_id: queue.id, active: true, limit_seconds: 60 }]
    policy.update!({ voice: 180, whatsapp: 180 }, voice_rules: rules, expected_revision: policy.revision)
    session = JrcContactCenter::CallSession.create!(
      account: @account, provider: 'jrc_pabx', correlation_id: SecureRandom.uuid, direction: 'inbound', status: 'connected',
      current_unit_id: queue.unit_id, current_queue_id: queue.id, started_at: 8.minutes.ago, answered_at: 7.minutes.ago
    )
    JrcContactCenter::CallLeg.create!(account: @account, call_session: session, account_user: operator, queue: queue,
                                      direction: 'inbound', status: 'connected', started_at: session.started_at, answered_at: session.answered_at)
    session.update!(status: 'ended', ended_at: 6.minutes.ago)
    record = JrcContactCenter::Qualification.find_by!(account: @account, account_user: operator, call_session: session)
    { call_session_id: session.id, qualification_id: record.id, qualification_started_at: record.started_at.iso8601(6) }
  end

  def team_source(operator, corporate: true)
    team = Team.create!(account: @account, name: "SYNTHETIC #{@project} operational team")
    team.add_members([operator.user_id])
    if corporate
      source = JrcCrm::UserBusinessUnit.find_by!(account: @account, user: operator.user)
      JrcCrm::TeamScope.create!(
        account: @account, team: team, scope: 'BUSINESS_UNIT',
        company_id: source.company_id, business_unit_id: source.business_unit_id
      )
      source.update!(team: team)
    end
    operator.custom_role.update!(permissions: [])
    JrcContactCenter::AccessGrant.create!(account: @account, team: team, allowed: %w[jrc_contact_center_view jrc_contact_center_operate])
    { team_id: team.id, team_name: team.name, operator_user_id: operator.user_id }
  end

  def assign_corporate_access(company, units, admin, scoped, operator)
    JrcCrm::UserBusinessUnit.create!(account: @account, user: admin.user, scope: 'GROUP', active: true, structure_managed: true)
    [scoped, operator].each do |member|
      JrcCrm::UserBusinessUnit.create!(account: @account, user: member.user, company: company, scope: 'BUSINESS_UNIT',
                                       business_unit_id: units.first.settings.fetch('business_unit_id'), active: true, structure_managed: true)
    end
  end

  def create_queues(units, operator)
    units.map do |unit|
      queue = JrcContactCenter::Queue.create!(account: @account, unit: unit, code: unit.code, name: "SYNTHETIC pause queue #{unit.code}")
      JrcContactCenter::QueueMembership.create!(account: @account, queue: queue, account_user: operator)
      queue
    end
  end

  def session_payload(units, queues, admin, scoped, operator)
    { account_id: @account.id, unit_id: units.first.id, denied_unit_id: units.last.id, queue_id: queues.first.id,
      denied_queue_id: queues.last.id, operator_id: operator.id, operator_role_id: operator.custom_role_id,
      administrator: admin.user.create_new_auth_token, operator: operator.user.create_new_auth_token, scoped: scoped.user.create_new_auth_token }
  end

  def create_units(company)
    %w[A B].map do |code|
      business = JrcCrm::BusinessUnit.create!(account: @account, operating_company: company, code: code, name: "SYNTHETIC pause #{code}")
      JrcContactCenter::Unit.create!(account: @account, code: code, name: "SYNTHETIC pause unit #{code}", kind: 'sac',
                                     settings: { issuer_company_id: company.id, business_unit_id: business.id })
    end
  end

  def create_member(kind, permissions, native_role, custom: true)
    user = User.new(name: "SYNTHETIC #{@project} #{kind}", email: "cc-pause-#{SecureRandom.hex(8)}@example.test",
                    password: JrcContactCenter::SyntheticPassword.generate, confirmed_at: Time.current)
    user.skip_confirmation_notification!
    user.save!
    role = CustomRole.create!(account: @account, name: "SYNTHETIC pause #{kind}", permissions: permissions) if custom
    member = AccountUser.create!(account: @account, user: user, custom_role: role, role: native_role)
    JrcContactCenter::AccessGrant.create!(account: @account, account_user: member, eligible: true)
    member
  end
end
