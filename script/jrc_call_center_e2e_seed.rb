# Executed only by the exclusive disposable runner. No provider is configured.
raise 'Owned synthetic runner required' unless ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted'

owned_database = Rails.env.test? && ENV['POSTGRES_HOST'] == '127.0.0.1'
owned_database &&= ActiveRecord::Base.connection_db_config.database == 'jrc_sd_bc_portal_concurrency_20261025_test'
raise 'Owned database required' unless owned_database
raise 'No external integration allowed' if ENV['SUPABASE_URL'].present? || ENV['SUPABASE_SERVICE_ROLE_KEY'].present?

require_relative 'jrc_call_center_synthetic_password'
require_relative 'jrc_call_center_audio_storage_guard'
JrcContactCenter::SyntheticAudioStorageGuard.call

account = Account.create!(name: 'SYNTHETIC Call Center QA', locale: 'pt_BR')
account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
other = Account.create!(name: 'SYNTHETIC denied Account')
admin = User.new(name: 'SYNTHETIC administrator', email: "cc-admin-#{SecureRandom.hex(6)}@example.test",
                 password: JrcContactCenter::SyntheticPassword.generate, confirmed_at: Time.current)
admin.skip_confirmation_notification!
admin.save!
role = CustomRole.create!(account: account, name: 'SYNTHETIC explicit QA', permissions: JrcContactCenter::ModulePolicy::PERMISSIONS)
AccountUser.create!(account: account, user: admin, role: :administrator, custom_role: role)
limited = User.new(name: 'SYNTHETIC read only', email: "cc-read-#{SecureRandom.hex(6)}@example.test",
                   password: JrcContactCenter::SyntheticPassword.generate, confirmed_at: Time.current)
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
                      password: JrcContactCenter::SyntheticPassword.generate, confirmed_at: Time.current)
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
                     password: JrcContactCenter::SyntheticPassword.generate, confirmed_at: Time.current)
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
    email: "cc-audit-#{SecureRandom.hex(6)}@example.test", password: JrcContactCenter::SyntheticPassword.generate, confirmed_at: Time.current
  )
  operator.skip_confirmation_notification!
  operator.save!
  permissions = %w[jrc_contact_center_view jrc_contact_center_audit]
  permissions.push('jrc_contact_center_supervise', 'jrc_contact_center_reports') if reports
  audit_role = CustomRole.create!(account: account, name: operator.name, permissions: permissions)
  AccountUser.create!(account: account, user: operator, role: :agent, custom_role: audit_role)
  JrcCrm::UserBusinessUnit.create!(
    account: account, user: operator, scope: 'BUSINESS_UNIT', business_unit: business_units.first,
    company: company, active: true, structure_managed: true
  )
  [operator, audit_role]
end

# Explicit synthetic eligibility, independent of native roles and team membership.
account.account_users.find_each do |member|
  JrcContactCenter::AccessGrant.create!(account: account, account_user: member, eligible: true)
end

# Explicit isolated infrastructure actor; never derive this role or scope for real users.
infrastructure = SuperAdmin.new(name: 'SYNTHETIC infrastructure administrator',
                                email: "cc-infrastructure-#{SecureRandom.hex(6)}@example.test",
                                password: JrcContactCenter::SyntheticPassword.generate, confirmed_at: Time.current)
infrastructure.skip_confirmation_notification!
infrastructure.save!
infrastructure_member = AccountUser.create!(account: account, user: infrastructure, role: :administrator, custom_role: role)
JrcContactCenter::AccessGrant.create!(account: account, account_user: infrastructure_member, eligible: true)
JrcCrm::UserBusinessUnit.create!(account: account, user: infrastructure, scope: 'GROUP', active: true, structure_managed: true)

# Separate synthetic targets for each browser project; no invitation or provider call.
access_targets = %w[desktop-light desktop-dark mobile-light mobile-dark].index_with do |project|
  recipients = %w[pending conflict peer enrollment enrollment_eligible enrollment_scoped].index_with do |kind|
    person = User.new(name: "SYNTHETIC #{project} #{kind}", email: "cc-#{kind}-#{SecureRandom.hex(6)}@example.test",
                      password: JrcContactCenter::SyntheticPassword.generate, confirmed_at: Time.current)
    person.skip_confirmation_notification!
    person.save!
    member = AccountUser.create!(account: account, user: person, role: :agent)
    if %w[peer enrollment_eligible enrollment_scoped].include?(kind)
      JrcContactCenter::AccessGrant.create!(account: account, account_user: member, eligible: true)
    end
    if kind == 'enrollment_eligible'
      JrcCrm::UserBusinessUnit.create!(account: account, user: person, scope: 'GROUP', active: true, structure_managed: true)
    elsif kind == 'enrollment_scoped'
      JrcCrm::UserBusinessUnit.create!(
        account: account, user: person, scope: 'BUSINESS_UNIT', business_unit: business_units.first,
        company: company, active: true, structure_managed: true
      )
    end
    { id: member.id, name: person.name }
  end
  team = Team.create!(account: account, name: "SYNTHETIC #{project} inherited")
  peer = account.account_users.find(recipients.fetch('peer').fetch(:id))
  team.add_members([peer.user_id])
  JrcContactCenter::AccessGrant.create!(account: account, team: team, allowed: [])
  recipients.merge('team' => { id: team.id, name: team.name })
end

# Dedicated navigation actors, independent of the existing popup targets.
navigation_targets = access_targets.keys.index_with do |project|
  navigation_user = User.new(name: "SYNTHETIC #{project} navigation", email: "cc-nav-#{SecureRandom.hex(6)}@example.test",
                             password: JrcContactCenter::SyntheticPassword.generate, confirmed_at: Time.current)
  navigation_user.skip_confirmation_notification!
  navigation_user.save!
  navigation_member = AccountUser.create!(account: account, user: navigation_user, role: :agent, custom_role: viewer)
  JrcContactCenter::AccessGrant.create!(account: account, account_user: navigation_member, eligible: true,
                                        denied: ['jrc_contact_center_reports'])
  navigation_team = Team.create!(account: account, name: "SYNTHETIC #{project} navigation")
  navigation_team.add_members([navigation_user.id])
  JrcContactCenter::AccessGrant.create!(account: account, team: navigation_team, allowed: ['jrc_contact_center_supervise'])
  { team_id: navigation_team.id, auth: navigation_user.create_new_auth_token }
end
21.times do |index|
  person = User.new(name: "SYNTHETIC pagination #{index.to_s.rjust(2, '0')}",
                    email: "cc-page-#{SecureRandom.hex(6)}@example.test",
                    password: JrcContactCenter::SyntheticPassword.generate, confirmed_at: Time.current)
  person.skip_confirmation_notification!
  person.save!
  AccountUser.create!(account: account, user: person, role: :agent)
end

session = { access_targets: access_targets, navigation_targets: navigation_targets, infrastructure: infrastructure.create_new_auth_token,
            account_id: account.id, other_account_id: other.id, unit_id: unit.id,
            administrator: admin.create_new_auth_token, viewer: limited.create_new_auth_token,
            delegated: delegated.create_new_auth_token,
            viewer_user_id: limited.id, viewer_role_id: viewer.id,
            viewer_account_user_id: account.account_users.find_by!(user: limited).id,
            restricted: restricted.create_new_auth_token, auditor: audit_operators.first.first.create_new_auth_token,
            audit_reader: audit_operators.last.first.create_new_auth_token, auditor_role_id: audit_operators.first.last.id,
            allowed_queue_id: scoped_queues.first.id, allowed_unit_id: scoped_units.first.id,
            denied_unit_id: scoped_units.last.id, denied_queue_id: scoped_queues.last.id,
            issuer_company_id: company.id, denied_business_unit_id: business_units.last.id }
require_relative 'jrc_call_center_ivr_seed'
session[:ivr_targets] = JrcContactCenter::SyntheticIvrSeed.call(projects: access_targets.keys)
# Independent native account graphs for calendar CRUD, scoped denials and revision races.
session[:calendar_targets] = JrcContactCenter::SyntheticIvrSeed.call(projects: access_targets.keys)
# Independent native scopes prevent audio mutations from reusing earlier IVR scenarios.
session[:ivr_audio_targets] = JrcContactCenter::SyntheticIvrSeed.call(projects: access_targets.keys)
require_relative 'jrc_call_center_ivr_audio_seed'
JrcContactCenter::SyntheticIvrAudioSeed.call(targets: session[:ivr_audio_targets])
# Independent account graph: never share mutable roles/forms with the existing IVR cases.
session[:acw_form_targets] = JrcContactCenter::SyntheticIvrSeed.call(projects: access_targets.keys)
session[:acw_form_targets].each_value do |target|
  owned_account = Account.find(target.fetch(:account_id))
  email = target.fetch(:administrator).fetch('uid')
  owned_user = owned_account.users.find_by!(email: email)
  owned_member = owned_account.account_users.find_by!(user: owned_user)
  owned_context = { account: owned_account, account_user: owned_member, user: owned_member.user }
  definition = { 'fields' => [{ 'key' => 'detail', 'label' => 'SYNTHETIC question', 'type' => 'text', 'required' => true }] }
  21.times do |index|
    values = { name: "SYNTHETIC page #{index.to_s.rjust(2, '0')}", status: 'active', definition: definition,
               request_id: SecureRandom.uuid, expected_revision: 0 }
    JrcContactCenter::AcwFormWrite.new(context: owned_context).call(input: JrcContactCenter::AcwFormInput.new(**values))
  end
end
require_relative 'jrc_call_center_customer_master_seed'
session[:customer_master_targets] = JrcContactCenter::SyntheticCustomerMasterSeed.call(projects: access_targets.keys)
require_relative 'jrc_call_center_pause_seed'
session[:pause_targets] = JrcContactCenter::SyntheticPauseSeed.call(projects: access_targets.keys)
# Independent existing IVR account graph; only local policy intent, no provider configuration.
session[:recording_policy_targets] = JrcContactCenter::SyntheticIvrSeed.call(projects: access_targets.keys)
session[:recording_policy_targets].each_value do |target|
  owned_account = Account.find(target.fetch(:account_id))
  owned_unit = JrcContactCenter::Unit.where(account: owned_account).find(target.fetch(:allowed_unit_id))
  20.times do |index|
    JrcContactCenter::Queue.create!(account: owned_account, unit: owned_unit, code: "SYNTHETIC-POLICY-#{index}",
                                   name: "SYNTHETIC policy queue #{index.to_s.rjust(2, '0')}")
  end
end
# Auth material is ephemeral, mode 0600, excluded from uploaded evidence.
File.write('/tmp/call-center-e2e-session.private', session.to_json, perm: 0o600)
puts({ account_id: account.id, synthetic: true, provider_configured: false }.to_json)
