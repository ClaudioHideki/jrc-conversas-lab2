require 'json'
raise 'Wrong test database' unless ActiveRecord::Base.connection_db_config.database == 'precimech_hotfix_test'
raise 'Wrong test host' unless ENV.fetch('POSTGRES_HOST') == 'precimech-hotfix-db-20261028'
ActiveJob::Base.queue_adapter = :test
suffix = SecureRandom.hex(5)
account = Account.create!(name: "Precimech isolated #{suffix}")
admin = User.new(email: "precimech-admin-#{suffix}@example.test", name: 'Test Admin', password: 'LocalTestOnly2026!')
admin.skip_confirmation!
admin.save!
AccountUser.create!(account: account, user: admin, role: :administrator)
agent = User.new(email: "precimech-agent-#{suffix}@example.test", name: 'Test Agent', password: 'LocalTestOnly2026!')
agent.skip_confirmation!
agent.save!
AccountUser.create!(account: account, user: agent, role: :agent)
other_account = Account.create!(name: "Other isolated #{suffix}")
pipeline = JrcCrm::Pipeline.create!(account: account, name: 'Test', key: suffix, position: 1)
stage = JrcCrm::Stage.create!(account: account, pipeline: pipeline, name: 'Test', key: suffix, position: 1)
new_contact = ->(owner = account) { Contact.create!(account: owner, name: 'Test Contact', email: "#{SecureRandom.hex(6)}@example.test") }
session = ActionDispatch::Integration::Session.new(Rails.application)
session.host! 'localhost'
results = []
check = lambda do |label, condition|
  raise "FAIL: #{label}" unless condition
  results << label
end
request_delete = lambda do |contact, user = admin|
  session.delete("/api/v1/accounts/#{account.id}/contacts/#{contact.id}", headers: user.create_new_auth_token)
  session.response.status
end

plain = new_contact.call
check.call('plain contact deletes', request_delete.call(plain) == 200 && !Contact.exists?(plain.id))
foreign = new_contact.call(other_account)
check.call('other account remains isolated', request_delete.call(foreign) == 404 && Contact.exists?(foreign.id))
protected_contact = new_contact.call
check.call('agent cannot delete', request_delete.call(protected_contact, agent) == 401 && Contact.exists?(protected_contact.id))
online = new_contact.call
OnlineStatusTracker.update_presence(account.id, 'Contact', online.id)
check.call('online contact is preserved', request_delete.call(online) == 422 && Contact.exists?(online.id))

secondary = new_contact.call
deal = JrcCrm::Deal.create!(account: account, pipeline: pipeline, stage: stage, owner: admin, title: 'Retained commercial record')
link = JrcCrm::DealContact.create!(deal: deal, contact: secondary)
if ENV['HOTFIX_EXPECTED'] == 'true'
  check.call('secondary CRM link is deleted synchronously', request_delete.call(secondary) == 200 && !Contact.exists?(secondary.id) && !JrcCrm::DealContact.exists?(link.id))
  check.call('deal itself is preserved', JrcCrm::Deal.exists?(deal.id))
else
  begin
    secondary.destroy!
    raise 'Original foreign-key defect did not reproduce'
  rescue ActiveRecord::InvalidForeignKey
    check.call('original foreign-key defect reproduced', Contact.exists?(secondary.id) && JrcCrm::DealContact.exists?(link.id))
  end
end

primary = new_contact.call
primary_deal = JrcCrm::Deal.create!(account: account, pipeline: pipeline, stage: stage, owner: admin, contact: primary, title: 'Protected primary record')
primary_link_id = primary.jrc_crm_deal_contacts.pick(:id)
if ENV['HOTFIX_EXPECTED'] == 'true'
  check.call('primary reference returns clear 422', request_delete.call(primary) == 422 && JSON.parse(session.response.body)['message'] == I18n.t('contacts.delete.referenced'))
  check.call('rollback preserves contact, link and commercial history', Contact.exists?(primary.id) && JrcCrm::Deal.exists?(primary_deal.id) && JrcCrm::DealContact.exists?(primary_link_id))
end
report = { mode: ENV['HOTFIX_EXPECTED'] == 'true' ? 'hotfix' : 'original', stage: ENV.fetch('HOTFIX_STAGE', 'source'), passed: results.size, checks: results }
File.write("/validation/backend-#{report[:mode]}-#{report[:stage]}.json", JSON.pretty_generate(report))
puts JSON.pretty_generate(report)
