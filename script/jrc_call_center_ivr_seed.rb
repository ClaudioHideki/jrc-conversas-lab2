# Dedicated accounts keep the 96 existing Chrome cases independent from local IVR mutations.
class JrcContactCenter::SyntheticIvrSeed
  def self.call(projects:)
    owned = owned_runner? && owned_resources?
    raise 'Owned synthetic IVR runner required' unless owned

    projects.index_with { |project| new(project).call }
  end

  def self.owned_runner?
    ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' && Rails.env.test?
  end

  def self.owned_resources?
    config = ActiveRecord::Base.connection_db_config
    config.database == 'jrc_sd_bc_portal_concurrency_20261025_test' && config.configuration_hash[:host] == '127.0.0.1' &&
      ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15'
  end

  private_class_method :new, :owned_runner?, :owned_resources?

  def initialize(project)
    @project = project
    @account = Account.create!(name: "SYNTHETIC IVR #{project}", locale: 'pt_BR')
    @account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
  end

  def call
    company = JrcCustomers::Company.create!(account: @account, name: "SYNTHETIC IVR issuer #{@project}", relationship_type: 'internal', active: true)
    units = create_units(company)
    admin = create_operator('administrator', JrcContactCenter::ModulePolicy::PERMISSIONS)
    scoped = create_operator('scoped', %w[jrc_contact_center_view jrc_contact_center_configure])
    JrcCrm::UserBusinessUnit.create!(account: @account, user: admin.user, scope: 'GROUP', active: true, structure_managed: true)
    JrcCrm::UserBusinessUnit.create!(account: @account, user: scoped.user, scope: 'BUSINESS_UNIT', company: company,
                                     business_unit_id: units.first.reload.settings.fetch('business_unit_id'), active: true, structure_managed: true)
    queue = JrcContactCenter::Queue.create!(account: @account, unit: units.first, code: 'VOICE', name: 'SYNTHETIC IVR voice')
    { account_id: @account.id, allowed_unit_id: units.first.id, denied_unit_id: units.last.id, queue_id: queue.id,
      scoped_member_id: scoped.id, administrator: admin.user.create_new_auth_token, scoped: scoped.user.create_new_auth_token }
  end

  private

  def create_units(company)
    %w[A B].map do |code|
      business = JrcCrm::BusinessUnit.create!(account: @account, operating_company: company,
                                              name: "SYNTHETIC IVR business #{code}", code: code, active: true)
      JrcContactCenter::Unit.create!(account: @account, code: code, name: "SYNTHETIC IVR unit #{code}", kind: 'sac',
                                     settings: { issuer_company_id: company.id, business_unit_id: business.id })
    end
  end

  def create_operator(kind, permissions)
    person = User.new(name: "SYNTHETIC IVR #{@project} #{kind}", email: "cc-ivr-#{SecureRandom.hex(8)}@example.test",
                      password: JrcContactCenter::SyntheticPassword.generate, confirmed_at: Time.current)
    person.skip_confirmation_notification!
    person.save!
    role = CustomRole.create!(account: @account, name: "SYNTHETIC IVR #{kind}", permissions: permissions)
    member = AccountUser.create!(account: @account, user: person, role: :administrator, custom_role: role)
    JrcContactCenter::AccessGrant.create!(account: @account, account_user: member, eligible: true)
    member
  end
end
