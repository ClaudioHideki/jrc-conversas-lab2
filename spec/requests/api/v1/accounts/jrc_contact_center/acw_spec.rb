# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Contact Center ACW persistent API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { agent.create_new_auth_token }
  let(:member) { account.account_users.find_by!(user: agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center" }
  let(:channel) { create(:channel_whatsapp, account: account, phone_number: "+5599#{SecureRandom.random_number(10**9).to_s.rjust(9, '0')}") }
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: agent) }
  before do
    stub_request(:post, 'https://waba.360dialog.io/v1/configs/webhook').to_return(status: 200, body: '{}')
    stub_request(:get, 'https://waba.360dialog.io/v1/configs/templates').to_return(status: 200, body: '{"waba_templates":[]}', headers: { 'Content-Type' => 'application/json' })
    account.enable_features!('jrc_contact_center')
    create(:inbox_member, inbox: inbox, user: agent)
  end

  it 'lets agents read explicit backend defaults without changing administrative settings' do
    get "#{base}/acw_policy", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['item']).to include('limits' => { 'voice' => 180, 'whatsapp' => 180 }, 'require_reason' => true, 'require_result' => true)
    patch "#{base}/acw_policy", headers: headers, as: :json, params: { limits: { voice: 12, whatsapp: 34 } }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'lets only authorized administration save independent per-account channel limits' do
    patch "#{base}/acw_policy", headers: admin.create_new_auth_token, as: :json, params: { limits: { voice: 12, whatsapp: 34 } }
    expect(response).to have_http_status(:ok)
    expect(JrcContactCenter::AcwPolicy.new(account: account.reload).call[:limits]).to eq('voice' => 12, 'whatsapp' => 34)
    expect(JrcContactCenter::AcwPolicy.new(account: create(:account)).call[:limits]).to eq('voice' => 180, 'whatsapp' => 180)
  end

  it 'rejects invalid or missing limits rather than taking a frontend fallback' do
    patch "#{base}/acw_policy", headers: admin.create_new_auth_token, as: :json, params: { limits: { voice: 0, whatsapp: 9999 } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'keeps conversation open, persists tabulation, resolves atomically and exposes history' do
    post "#{base}/qualifications", headers: headers, as: :json, params: { conversation_id: conversation.display_id }
    expect(response).to have_http_status(:ok)
    id = response.parsed_body['item']['id']
    expect(conversation.reload.status).to eq('open')
    patch "#{base}/qualifications/#{id}", headers: headers, as: :json,
                                          params: { qualification: { reason_code: 'order', outcome_code: 'completed', notes: 'Persisted API note' } }
    expect(response).to have_http_status(:ok)
    expect(conversation.reload.status).to eq('resolved')
    get "#{base}/qualifications", headers: headers, as: :json, params: { conversation_id: conversation.display_id }
    expect(response.parsed_body['items'].first).to include('notes' => 'Persisted API note', 'channel' => 'whatsapp', 'account_id' => account.id)
    expect(response.parsed_body['items'].first['completed_at']).to be_present
  end

  it 'rejects direct native API resolution before tabulation' do
    post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/toggle_status", headers: headers, as: :json,
                                                                                             params: { status: 'resolved' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(conversation.reload.status).to eq('open')
  end

  it 'rejects update from another Account and foreign attendance identifiers' do
    other = create(:account)
    foreign_agent = create(:user, account: other, role: :agent)
    post "#{base}/qualifications", headers: foreign_agent.create_new_auth_token, as: :json, params: { conversation_id: conversation.display_id }
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::Qualification.where(account: account)).to be_empty
  end

  it 'cannot spoof the agent or force completion with missing mandatory fields' do
    post "#{base}/qualifications", headers: headers, as: :json, params: { conversation_id: conversation.display_id, account_user_id: 999_999 }
    id = response.parsed_body['item']['id']
    expect(JrcContactCenter::Qualification.find(id).account_user_id).to eq(member.id)
    patch "#{base}/qualifications/#{id}", headers: headers, as: :json, params: { qualification: { notes: 'No required fields' } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::Qualification.find(id).completed_at).to be_nil
  end
end
