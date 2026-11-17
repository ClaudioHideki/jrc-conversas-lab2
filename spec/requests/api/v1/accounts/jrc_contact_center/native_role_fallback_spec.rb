require 'rails_helper'

RSpec.describe 'Call Center authority on native role fallback', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator, name: 'SYNTHETIC limited admin') }
  let!(:headers) { actor.create_new_auth_token }
  let(:actor_link) { account.account_users.find_by!(user: actor) }
  let(:actor_role) { create(:custom_role, account: account, permissions: ['jrc_contact_center_view']) }
  let(:recipient) { create(:user, :contact_center_eligible, account: account, role: :agent, name: 'SYNTHETIC recipient') }
  let(:recipient_link) { account.account_users.find_by!(user: recipient) }
  let(:recipient_role) { create(:custom_role, account: account, permissions: ['jrc_contact_center_view']) }
  let(:agents_url) { "/api/v1/accounts/#{account.id}/agents" }
  let(:roles_url) { "/api/v1/accounts/#{account.id}/custom_roles" }

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
    actor_link.update!(custom_role: actor_role)
    recipient_link.update!(custom_role: recipient_role)
  end

  [nil, ''].each do |value|
    it "denies removing a restrictive own profile using #{value.inspect} without partial name changes" do
      attributes = { agent: { name: 'Forbidden' }, custom_role_id: value }
      patch "#{agents_url}/#{actor.id}", headers: headers, params: attributes, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(actor.reload.name).to eq('SYNTHETIC limited admin')
      expect(actor_link.reload.custom_role_id).to eq(actor_role.id)
    end
  end

  it 'denies clearing another agent profile when operate would be newly granted' do
    patch "#{agents_url}/#{recipient.id}", headers: headers, params: { agent: { name: 'Forbidden' }, custom_role_id: nil }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(recipient.reload.name).to eq('SYNTHETIC recipient')
    expect(recipient_link.reload.custom_role_id).to eq(recipient_role.id)
  end

  it 'allows clearing the profile when the actor holds every resulting capability' do
    actor_link.update!(custom_role: nil)
    patch "#{agents_url}/#{recipient.id}", headers: headers, params: { agent: { name: 'SYNTHETIC permitted' }, custom_role_id: nil }, as: :json
    expect(response).to have_http_status(:ok)
    expect(recipient.reload.name).to eq('SYNTHETIC permitted')
    expect(recipient_link.reload.custom_role_id).to be_nil
  end

  it 'denies native promotion of an unprofiled agent above actor authority' do
    recipient_link.update!(custom_role: nil)
    patch "#{agents_url}/#{recipient.id}", headers: headers, params: { agent: { role: 'administrator' } }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(recipient_link.reload.role).to eq('agent')
  end

  it 'preserves a custom profile when the native role enum changes without removing the profile' do
    patch "#{agents_url}/#{recipient.id}", headers: headers, params: { agent: { role: 'administrator' } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(recipient_link.reload.custom_role_id).to eq(recipient_role.id)
    policy = JrcContactCenter::ModulePolicy.new({ account: account, account_user: recipient_link, user: recipient }, :contact_center)
    expect(policy.configure?).to be(false)
  end

  it 'creates an unprofiled agent pending explicit eligibility without granting legacy authority' do
    post agents_url, headers: headers,
                     params: { agent: { name: 'SYNTHETIC denied', email: 'cc-denied@example.test', role: 'agent' } }, as: :json
    expect(response).to have_http_status(:ok)
    created = account.users.find_by!(email: 'cc-denied@example.test')
    link = account.account_users.find_by!(user: created)
    expect(JrcContactCenter::AccessGrant.exists?(account_user: link)).to be(false)
    policy = JrcContactCenter::ModulePolicy.new({ account: account, account_user: link, user: created }, :contact_center)
    expect(policy.effective_permissions).to eq([])
  end

  it 'keeps a bulk-created agent pending rather than activating implicit Call Center access' do
    post "#{agents_url}/bulk_create", headers: headers, params: { emails: ['cc-bulk-denied@example.test'] }, as: :json
    expect(response).to have_http_status(:ok)
    created = account.users.find_by!(email: 'cc-bulk-denied@example.test')
    link = account.account_users.find_by!(user: created)
    expect(JrcContactCenter::AccessGrant.exists?(account_user: link)).to be(false)
  end

  it 'permits creating a user with an explicit role within actor authority' do
    post agents_url, headers: headers,
                     params: { agent: { name: 'SYNTHETIC permitted', email: 'cc-explicit@example.test', role: 'agent' },
                               custom_role_id: recipient_role.id }, as: :json
    expect(response).to have_http_status(:ok)
    created = account.users.find_by!(email: 'cc-explicit@example.test')
    expect(account.account_users.find_by!(user: created).custom_role_id).to eq(recipient_role.id)
  end

  it 'denies deletion of an assigned role when nullification would increase recipient access' do
    count = Enterprise::AuditLog.where(associated: account).count
    delete "#{roles_url}/#{recipient_role.id}", headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(recipient_link.reload.custom_role_id).to eq(recipient_role.id)
    expect(CustomRole.exists?(recipient_role.id)).to be(true)
    expect(Enterprise::AuditLog.where(associated: account).count).to eq(count)
  end

  it 'denies deleting the restricted own profile to activate administrator fallback' do
    delete "#{roles_url}/#{actor_role.id}", headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(actor_link.reload.custom_role_id).to eq(actor_role.id)
  end

  it 'allows deletion when the actor has the resulting native authorities' do
    actor_link.update!(custom_role: nil)
    delete "#{roles_url}/#{recipient_role.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(recipient_link.reload.custom_role_id).to be_nil
    expect(CustomRole.exists?(recipient_role.id)).to be(false)
  end

  it 'allows deleting an unused role without granting anything' do
    unused = create(:custom_role, account: account, permissions: ['jrc_contact_center_view'])
    delete "#{roles_url}/#{unused.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(CustomRole.exists?(unused.id)).to be(false)
  end

  it 'preserves native clearing when the Call Center feature is disabled' do
    account.disable_features!('jrc_contact_center')
    patch "#{agents_url}/#{recipient.id}", headers: headers, params: { agent: { name: 'SYNTHETIC other module' }, custom_role_id: nil }, as: :json
    expect(response).to have_http_status(:ok)
    expect(recipient_link.reload.custom_role_id).to be_nil
  end

  it 'does not resolve a profile from another account' do
    foreign = create(:custom_role, account: create(:account), permissions: ['jrc_contact_center_view'])
    attributes = { agent: { name: 'Forbidden' }, custom_role_id: foreign.id }
    patch "#{agents_url}/#{recipient.id}", headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:not_found)
    expect(recipient_link.reload.custom_role_id).to eq(recipient_role.id)
    expect(recipient.reload.name).to eq('SYNTHETIC recipient')
  end

  [[], {}, false, '0', '-1', '999999999999999999999999'].each do |value|
    it "rejects malformed role identifier #{value.inspect} instead of treating it as permission removal" do
      patch "#{agents_url}/#{recipient.id}", headers: headers, params: { agent: { name: 'Forbidden' }, custom_role_id: value }, as: :json
      expect(response).to have_http_status(:not_found)
      expect(recipient_link.reload.custom_role_id).to eq(recipient_role.id)
    end
  end
end
