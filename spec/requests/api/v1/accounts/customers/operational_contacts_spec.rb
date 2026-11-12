require 'rails_helper'

RSpec.describe 'Operational contacts', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/customers/operational_contacts" }

  before { account.enable_features!('jrc_customer_master') }

  it 'returns real authorized movement and bounded metadata, without mutating native records' do
    contact = create(:contact, account: account)
    conversation = create(:conversation, account: account, contact: contact, status: :open)
    before = [contact.reload.attributes, conversation.reload.attributes]
    get base, headers: headers, params: { per_page: 1, account_id: 0, user_id: 0, unit_id: 0 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').sole).to include('id' => contact.id, 'operational_status' => 'in_service')
    expect(response.parsed_body.fetch('meta')).to include('total' => 1, 'per_page' => 1, 'days' => 30)
    expect(response.headers['Cache-Control']).to include('no-store')
    expect([contact.reload.attributes, conversation.reload.attributes]).to eq(before)
  end

  it 'denies unauthenticated users, absent membership, revoked permissions and disabled feature' do
    get base
    expect(response).to have_http_status(:unauthorized)
    other = create(:user)
    get base, headers: other.create_new_auth_token
    expect(response).not_to have_http_status(:ok)
    account.disable_features!('jrc_customer_master')
    get base, headers: headers
    expect(response).to have_http_status(:unauthorized)
    account.enable_features!('jrc_customer_master')
    role = create(:custom_role, account: account, permissions: ['conversation_manage'])
    account.account_users.find_by!(user: actor).update!(role: :agent, custom_role: role)
    get base, headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects unsupported filter values and never accepts a foreign segment as a scope grant' do
    get base, headers: headers, params: { kind: 'invented' }
    expect(response).to have_http_status(:bad_request)
    foreign = create(:account)
    taxonomy = JrcCustomers::Taxonomy.create!(account: foreign, name: 'Foreign segment', kind: 'segment', selection_mode: 'classification')
    get base, headers: headers, params: { taxonomy_id: taxonomy.id }
    expect(response).to have_http_status(:not_found)
  end
end
