# Executed only by the exclusive disposable runner. No provider is configured.
raise 'Owned synthetic runner required' unless ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted'

owned_database = Rails.env.test? && ENV['POSTGRES_HOST'] == '127.0.0.1'
owned_database &&= ActiveRecord::Base.connection_db_config.database == 'jrc_sd_bc_portal_concurrency_20261025_test'
raise 'Owned database required' unless owned_database
raise 'No external integration allowed' if ENV['SUPABASE_URL'].present? || ENV['SUPABASE_SERVICE_ROLE_KEY'].present?

account = Account.create!(name: 'SYNTHETIC Call Center QA', locale: 'pt_BR')
account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
other = Account.create!(name: 'SYNTHETIC denied Account')
admin = User.new(name: 'SYNTHETIC administrator', email: "cc-admin-#{SecureRandom.hex(6)}@example.test",
                 password: SecureRandom.base64(32), confirmed_at: Time.current)
admin.skip_confirmation_notification!
admin.save!
role = CustomRole.create!(account: account, name: 'SYNTHETIC explicit QA', permissions: JrcContactCenter::ModulePolicy::PERMISSIONS)
AccountUser.create!(account: account, user: admin, role: :administrator, custom_role: role)
limited = User.new(name: 'SYNTHETIC read only', email: "cc-read-#{SecureRandom.hex(6)}@example.test",
                   password: SecureRandom.base64(32), confirmed_at: Time.current)
limited.skip_confirmation_notification!
limited.save!
viewer = CustomRole.create!(account: account, name: 'SYNTHETIC view only', permissions: ['jrc_contact_center_view'])
AccountUser.create!(account: account, user: limited, role: :agent, custom_role: viewer)
unit = JrcContactCenter::Unit.create!(account: account, name: 'SYNTHETIC primary', code: 'PRIMARY', kind: 'sac')
23.times do |index|
  JrcContactCenter::Queue.create!(account: account, unit: unit, code: "QUEUE-#{index}", name: "SYNTHETIC queue #{index.to_s.rjust(2, '0')}")
end
company = JrcCustomers::Company.create!(account: account, name: 'SYNTHETIC issuer', relationship_type: 'internal', active: true)
business_units = %w[A B].map do |code|
  JrcCrm::BusinessUnit.create!(account: account, operating_company: company, name: "SYNTHETIC unit #{code}", code: "UNIT-#{code}", active: true)
end
scoped_units = business_units.map do |business_unit|
  JrcContactCenter::Unit.create!(
    account: account, code: business_unit.code, name: business_unit.name, kind: 'sac',
    settings: { issuer_company_id: company.id, business_unit_id: business_unit.id }
  )
end
scoped_queues = scoped_units.map do |scoped_unit|
  JrcContactCenter::Queue.create!(account: account, unit: scoped_unit, code: scoped_unit.code, name: scoped_unit.name)
end
restricted = User.new(name: 'SYNTHETIC unit manager', email: "cc-unit-#{SecureRandom.hex(6)}@example.test",
                      password: SecureRandom.base64(32), confirmed_at: Time.current)
restricted.skip_confirmation_notification!
restricted.save!
restricted_role = CustomRole.create!(account: account, name: 'SYNTHETIC scoped configuration',
                                     permissions: %w[jrc_contact_center_view jrc_contact_center_configure])
AccountUser.create!(account: account, user: restricted, role: :administrator, custom_role: restricted_role)
JrcCrm::UserBusinessUnit.create!(
  account: account, user: restricted, scope: 'BUSINESS_UNIT', business_unit: business_units.first,
  company: company, active: true, structure_managed: true
)
delegated = User.new(name: 'SYNTHETIC limited role administrator', email: "cc-role-#{SecureRandom.hex(6)}@example.test",
                     password: SecureRandom.base64(32), confirmed_at: Time.current)
delegated.skip_confirmation_notification!
delegated.save!
delegated_role = CustomRole.create!(account: account, name: 'SYNTHETIC limited role administration',
                                    permissions: %w[jrc_contact_center_view jrc_contact_center_administer])
AccountUser.create!(account: account, user: delegated, role: :administrator, custom_role: delegated_role)
# Explicit synthetic organizational grants, independent from functional roles.
[admin, limited, delegated].each do |operator|
  JrcCrm::UserBusinessUnit.create!(account: account, user: operator, scope: 'GROUP', active: true, structure_managed: true)
end

# Explicit synthetic audit operators: no configuration/role administration grants.
audit_operators = [true, false].map do |reports|
  operator = User.new(
    name: reports ? 'SYNTHETIC scoped auditor' : 'SYNTHETIC audit reader',
    email: "cc-audit-#{SecureRandom.hex(6)}@example.test", password: SecureRandom.base64(32), confirmed_at: Time.current
  )
  operator.skip_confirmation_notification!
  operator.save!
  permissions = %w[jrc_contact_center_view jrc_contact_center_supervise jrc_contact_center_audit]
  permissions << 'jrc_contact_center_reports' if reports
  audit_role = CustomRole.create!(account: account, name: operator.name, permissions: permissions)
  AccountUser.create!(account: account, user: operator, role: :agent, custom_role: audit_role)
  JrcCrm::UserBusinessUnit.create!(
    account: account, user: operator, scope: 'BUSINESS_UNIT', business_unit: business_units.first,
    company: company, active: true, structure_managed: true
  )
  [operator, audit_role]
end

session = { account_id: account.id, other_account_id: other.id, unit_id: unit.id,
            administrator: admin.create_new_auth_token, viewer: limited.create_new_auth_token,
            delegated: delegated.create_new_auth_token,
            viewer_user_id: limited.id, viewer_role_id: viewer.id,
            viewer_account_user_id: account.account_users.find_by!(user: limited).id,
            restricted: restricted.create_new_auth_token, auditor: audit_operators.first.first.create_new_auth_token,
            audit_reader: audit_operators.last.first.create_new_auth_token, auditor_role_id: audit_operators.first.last.id,
            allowed_queue_id: scoped_queues.first.id, allowed_unit_id: scoped_units.first.id,
            denied_unit_id: scoped_units.last.id, denied_queue_id: scoped_queues.last.id,
            issuer_company_id: company.id, denied_business_unit_id: business_units.last.id }
# Auth material is ephemeral, mode 0600, excluded from uploaded evidence.
File.write('/tmp/call-center-e2e-session.private', session.to_json, perm: 0o600)
puts({ account_id: account.id, synthetic: true, provider_configured: false }.to_json)
