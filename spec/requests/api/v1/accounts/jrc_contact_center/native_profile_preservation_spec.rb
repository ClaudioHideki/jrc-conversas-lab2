require 'rails_helper'

RSpec.describe 'Call Center profile preservation through native agent updates', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator, name: 'SYNTHETIC profile actor') }
  let!(:headers) { actor.create_new_auth_token }
  let(:actor_link) { account.account_users.find_by!(user: actor) }
  let(:actor_role) { create(:custom_role, account: account, permissions: ['jrc_contact_center_view']) }
  let(:recipient) { create(:user, :contact_center_eligible, account: account, role: :agent, name: 'SYNTHETIC recipient') }
  let(:recipient_link) { account.account_users.find_by!(user: recipient) }
  let(:recipient_role) do
    create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_reports])
  end
  let(:base) { "/api/v1/accounts/#{account.id}/agents" }

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
    actor_link.update!(custom_role: actor_role)
    recipient_link.update!(custom_role: recipient_role)
  end

  it 'preserves the restricted profile when the administrator updates their own name without a role parameter' do
    patch "#{base}/#{actor.id}", headers: headers, params: { agent: { name: 'SYNTHETIC renamed actor' } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(actor.reload.name).to eq('SYNTHETIC renamed actor')
    expect(actor_link.reload.custom_role_id).to eq(actor_role.id)
    policy = JrcContactCenter::ModulePolicy.new({ account: account, user: actor, account_user: actor_link }, :contact_center)
    expect(policy.configure?).to be(false)
    expect(policy.supervise?).to be(false)
    expect(policy.reports?).to be(false)
  end

  it 'preserves another user profile and its existing Call Center authorities on a partial name update' do
    patch "#{base}/#{recipient.id}", headers: headers, params: { agent: { name: 'SYNTHETIC partial update' } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(recipient.reload.name).to eq('SYNTHETIC partial update')
    expect(recipient_link.reload.custom_role_id).to eq(recipient_role.id)
    expect(recipient_link.permissions).to include('jrc_contact_center_reports')
  end

  it 'changes availability without removing the custom role or its unrelated module permissions' do
    unrelated_role = create(:custom_role, account: account, permissions: ['contact_manage'])
    recipient_link.update!(custom_role: unrelated_role)
    patch "#{base}/#{recipient.id}", headers: headers, params: { agent: { availability: 'offline' } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(recipient_link.reload.availability).to eq('offline')
    expect(recipient_link.custom_role_id).to eq(unrelated_role.id)
    expect(recipient_link.permissions).to include('contact_manage')
  end

  it 'preserves the explicit native role-assignment contract for other module profiles' do
    explicit = create(:custom_role, account: account, permissions: ['contact_manage'])
    patch "#{base}/#{recipient.id}", headers: headers,
                                     params: { agent: { name: 'SYNTHETIC explicit profile' }, custom_role_id: explicit.id }, as: :json
    expect(response).to have_http_status(:ok)
    expect(recipient_link.reload.custom_role_id).to eq(explicit.id)
    expect(recipient_link.permissions).to include('contact_manage')
  end

  it 'preserves non-Call-Center profiles when the Call Center feature is disabled' do
    account.disable_features!('jrc_contact_center')
    unrelated_role = create(:custom_role, account: account, permissions: ['contact_manage'])
    recipient_link.update!(custom_role: unrelated_role)
    patch "#{base}/#{recipient.id}", headers: headers, params: { agent: { name: 'SYNTHETIC other modules' } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(recipient.reload.name).to eq('SYNTHETIC other modules')
    expect(recipient_link.reload.custom_role_id).to eq(unrelated_role.id)
  end

  it 'does not mutate a user or profile from another account' do
    foreign_account = create(:account)
    foreign = create(:user, :contact_center_eligible, account: foreign_account, name: 'SYNTHETIC foreign')
    foreign_role = create(:custom_role, account: foreign_account, permissions: ['contact_manage'])
    foreign_link = foreign_account.account_users.find_by!(user: foreign)
    foreign_link.update!(custom_role: foreign_role)
    patch "#{base}/#{foreign.id}", headers: headers, params: { agent: { name: 'Forbidden' } }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(foreign.reload.name).to eq('SYNTHETIC foreign')
    expect(foreign_link.reload.custom_role_id).to eq(foreign_role.id)
  end
end
