# Executed only by the exclusive disposable runner. No provider is configured.
raise 'Owned synthetic runner required' unless ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted'
owned_database = Rails.env.test? && ENV['POSTGRES_HOST'] == '127.0.0.1'
owned_database &&= ActiveRecord::Base.connection_db_config.database == 'jrc_sd_bc_portal_concurrency_20261025_test'
raise 'Owned database required' unless owned_database
raise 'No external integration allowed' if ENV['SUPABASE_URL'].present? || ENV['SUPABASE_SERVICE_ROLE_KEY'].present?

account = Account.create!(name: 'SYNTHETIC Call Center QA', locale: 'pt_BR')
account.enable_features!('jrc_contact_center')
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
session = { account_id: account.id, other_account_id: other.id, unit_id: unit.id,
            administrator: admin.create_new_auth_token, viewer: limited.create_new_auth_token }
# Auth material is ephemeral, mode 0600, excluded from uploaded evidence.
File.write('/tmp/call-center-e2e-session.private', session.to_json, perm: 0o600)
puts({ account_id: account.id, synthetic: true, provider_configured: false }.to_json)
