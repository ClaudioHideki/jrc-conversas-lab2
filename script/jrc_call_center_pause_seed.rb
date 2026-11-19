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
      %w[editor operations withdrawal duration acw routing team_withdrawal].index_with { |kind| new("#{project}-#{kind}").call }
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
    payload
  end

  private

  def team_source(operator)
    team = Team.create!(account: @account, name: "SYNTHETIC #{@project} operational team")
    team.add_members([operator.user_id])
    source = JrcCrm::UserBusinessUnit.find_by!(account: @account, user: operator.user)
    JrcCrm::TeamScope.create!(account: @account, team: team, scope: 'BUSINESS_UNIT',
                             company_id: source.company_id, business_unit_id: source.business_unit_id)
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
