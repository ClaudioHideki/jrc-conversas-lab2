# Only owned synthetic resources; no inbox/channel or PABX is configured.
class JrcContactCenter::SyntheticCustomerMasterSeed
  OPERATOR_PERMISSIONS = %w[contact_manage jrc_contact_center_view jrc_contact_center_operate].freeze

  def self.call(projects:)
    config = ActiveRecord::Base.connection_db_config
    owned = [
      ENV['GITHUB_ACTIONS'] == 'true', ENV['RUNNER_ENVIRONMENT'] == 'github-hosted', Rails.env.test?,
      config.database == 'jrc_sd_bc_portal_concurrency_20261025_test', config.configuration_hash[:host] == '127.0.0.1',
      ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15'
    ].all?
    raise 'Owned synthetic customer master runner required' unless owned

    projects.each_with_index.to_h { |project, index| [project, new(project, index).call] }
  end
  private_class_method :new

  def initialize(project, index)
    @project = project
    @index = index
    @account = Account.create!(name: "SYNTHETIC linked master #{project}", locale: 'pt_BR')
    @account.enable_features!('jrc_contact_center', 'custom_roles', 'jrc_customer_master', 'crm')
  end

  def call
    units = create_units
    operator = create_operator('operator', OPERATOR_PERMISSIONS, :agent)
    admin = create_operator('administrator', [*JrcContactCenter::ModulePolicy::PERMISSIONS, 'contact_manage'], :administrator)
    JrcCrm::UserBusinessUnit.create!(account: @account, user: admin.user, scope: 'GROUP', active: true, structure_managed: true)
    JrcCrm::UserBusinessUnit.create!(account: @account, user: operator.user, scope: 'BUSINESS_UNIT', company: units.first.fetch(:company),
                                     business_unit: units.first.fetch(:business), active: true, structure_managed: true)
    contacts = create_contacts(units)
    calls = units.zip(contacts).map { |unit, contact| create_call(unit.fetch(:unit), contact, operator) }
    unlinked = create_call(units.first.fetch(:unit), nil, operator, phone: contacts.first.phone_number)
    session_payload(operator, admin, contacts, calls, unlinked)
  end

  private

  def create_units
    %w[A B].map do |code|
      company = @account.master_companies.create!(name: "SYNTHETIC master issuer #{code}", relationship_type: 'internal')
      business = JrcCrm::BusinessUnit.create!(account: @account, operating_company: company, code: code, name: "SYNTHETIC master business #{code}")
      unit = JrcContactCenter::Unit.create!(account: @account, code: code, name: "SYNTHETIC master unit #{code}", kind: 'sac',
                                            settings: { issuer_company_id: company.id, business_unit_id: business.id })
      { company: company, business: business, unit: unit }
    end
  end

  def create_contacts(units)
    units.each_with_index.map do |unit, index|
      @account.contacts.create!(name: "SYNTHETIC master contact #{index}", company_id: unit.fetch(:company).id,
                                phone_number: "+551197770#{format('%04d', (@index * 10) + index)}")
    end
  end

  def create_call(unit, contact, operator, phone: nil)
    call = JrcContactCenter::CallSession.create!(
      account: @account, contact: contact, current_unit: unit, ani: phone || contact.phone_number,
      provider: 'synthetic-local', correlation_id: SecureRandom.uuid, direction: 'inbound', status: 'connected', started_at: Time.current
    )
    JrcContactCenter::CallLeg.create!(account: @account, call_session: call, account_user: operator,
                                      started_at: Time.current, direction: 'inbound', status: 'connected')
    call
  end

  def create_operator(kind, permissions, native_role)
    person = User.new(name: "SYNTHETIC master #{@project} #{kind}", email: "cc-master-#{SecureRandom.hex(8)}@example.test",
                      password: JrcContactCenter::SyntheticPassword.generate, confirmed_at: Time.current)
    person.skip_confirmation_notification!
    person.save!
    role = CustomRole.create!(account: @account, name: "SYNTHETIC master #{kind}", permissions: permissions)
    member = AccountUser.create!(account: @account, user: person, role: native_role, custom_role: role)
    JrcContactCenter::AccessGrant.create!(account: @account, account_user: member, eligible: true)
    member
  end

  def foreign_contact
    account = Account.create!(name: "SYNTHETIC denied master #{@project}", locale: 'pt_BR')
    account.contacts.create!(name: 'SYNTHETIC foreign master', phone_number: "+551197779#{format('%04d', @index)}")
  end

  def session_payload(operator, admin, contacts, calls, unlinked)
    foreign = foreign_contact
    { account_id: @account.id, contact_id: contacts.first.id, denied_contact_id: contacts.last.id,
      call_id: calls.first.id, denied_call_id: calls.last.id, unlinked_call_id: unlinked.id,
      company_id: contacts.first.company_id, foreign_account_id: foreign.account_id, foreign_contact_id: foreign.id,
      user_id: operator.user_id, role_id: operator.custom_role_id, operator: operator.user.create_new_auth_token,
      administrator: admin.user.create_new_auth_token }
  end
end
