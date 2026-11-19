# Exclusive synthetic accounts; no channels, inboxes or PABX configuration.
class JrcContactCenter::SyntheticPauseSeed
  def self.call(projects:)
    config = ActiveRecord::Base.connection_db_config
    owned = [
      ENV['GITHUB_ACTIONS'] == 'true', ENV['RUNNER_ENVIRONMENT'] == 'github-hosted', Rails.env.test?,
      config.database == 'jrc_sd_bc_portal_concurrency_20261025_test', config.configuration_hash[:host] == '127.0.0.1',
      ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15'
    ].all?
    raise 'Owned synthetic pause runner required' unless owned

    projects.index_with do |project|
      %w[editor operations withdrawal duration acw routing team_withdrawal acw_draft acw_review].index_with do |kind|
        new("#{project}-#{kind}").call
      end
    end
  end
  private_class_method :new

  def initialize(project)
    @project = project
    @account = Account.create!(name: "SYNTHETIC pause #{project}", locale: 'pt_BR')
    @account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
  end

  def call
    company = @account.master_companies.create!(name: 'SYNTHETIC pause issuer', relationship_type: 'internal')
    units = create_units(company)
    admin = create_member('administrator', JrcContactCenter::ModulePolicy::PERMISSIONS, :administrator)
    scoped = create_member('scoped', JrcContactCenter::ModulePolicy::PERMISSIONS, :administrator)
    operator = create_member('operator', %w[jrc_contact_center_view jrc_contact_center_operate], :agent)
    assign_corporate_access(company, units, admin, scoped, operator)
    queues = create_queues(units, operator)
    payload = session_payload(units, queues, admin, scoped, operator)
    payload.merge!(team_source(operator)) if @project.end_with?('-team_withdrawal')
    payload.merge!(pending_qualification(queues.first, operator)) if @project.end_with?('-acw_draft', '-acw_review')
    payload
  end

  private

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

  def team_source(operator)
    team = Team.create!(account: @account, name: "SYNTHETIC #{@project} operational team")
    team.add_members([operator.user_id])
    source = JrcCrm::UserBusinessUnit.find_by!(account: @account, user: operator.user)
    JrcCrm::TeamScope.create!(
      account: @account, team: team, scope: 'BUSINESS_UNIT',
      company_id: source.company_id, business_unit_id: source.business_unit_id
    )
    source.update!(team: team)
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
      administrator: admin.user.create_new_auth_token, operator: operator.user.create_new_auth_token,
      scoped: scoped.user.create_new_auth_token }
  end

  def create_units(company)
    %w[A B].map do |code|
      business = JrcCrm::BusinessUnit.create!(account: @account, operating_company: company, code: code, name: "SYNTHETIC pause #{code}")
      JrcContactCenter::Unit.create!(account: @account, code: code, name: "SYNTHETIC pause unit #{code}", kind: 'sac',
                                     settings: { issuer_company_id: company.id, business_unit_id: business.id })
    end
  end

  def create_member(kind, permissions, native_role)
    user = User.new(name: "SYNTHETIC #{@project} #{kind}", email: "cc-pause-#{SecureRandom.hex(8)}@example.test",
                    password: JrcContactCenter::SyntheticPassword.generate, confirmed_at: Time.current)
    user.skip_confirmation_notification!
    user.save!
    role = CustomRole.create!(account: @account, name: "SYNTHETIC pause #{kind}", permissions: permissions)
    member = AccountUser.create!(account: @account, user: user, custom_role: role, role: native_role)
    JrcContactCenter::AccessGrant.create!(account: @account, account_user: member, eligible: true)
    member
  end
end
