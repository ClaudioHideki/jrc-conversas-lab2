require 'rails_helper'

RSpec.describe 'NICO historical authorization', type: :request do
  let(:account) { create(:account, custom_attributes: { 'nico_enabled' => true }) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account) }
  let(:lead) { create(:jrc_crm_lead, account: account, owner: user, contact: conversation.contact, notes: 'Restricted CRM note') }
  let(:run) { JrcNico::Run.create!(account: account, user: user, conversation: conversation, request_id: SecureRandom.uuid, message: 'Resumo') }
  let(:path) { "/api/v1/accounts/#{account.id}/jrc_nico/runs" }
  let(:headers) { user.create_new_auth_token }
  before do
    account.enable_features!('jrc_crm')
    account.account_users.find_by!(user_id: user.id).update!(crm_enabled: true)
    create(:inbox_member, inbox: conversation.inbox, user: user)
    lead
    client = instance_double(JrcNico::RuntimeClient)
    allow(JrcNico::RuntimeClient).to receive(:new).and_return(client)
    allow(client).to receive(:analyze).and_return({ 'summary' => 'Restricted CRM note', 'evidence' => [], 'mode' => 'fixture', 'usage' => nil })
    JrcNico::AnalyzeJob.perform_now(run.id)
    expect(run.reload.status).to eq('completed')
  end

  it 'hides every historical serialization after CRM permission is revoked, even without model citations' do
    account.disable_features!('jrc_crm')
    get "#{path}/#{run.id}", headers: headers
    expect(response.body).not_to include('Restricted CRM note')
    get path, params: { conversation_id: conversation.display_id }, headers: headers
    expect(response.body).not_to include('Restricted CRM note')
    post path, params: { conversation_id: conversation.display_id, request_id: run.request_id, message: run.message }, headers: headers, as: :json
    expect(response.body).not_to include('Restricted CRM note')
    post "#{path}/#{run.id}/cancel", headers: headers, as: :json
    expect(response.body).not_to include('Restricted CRM note')
  end

  it 'hides a previous summary after the referenced lead changes owner' do
    lead.update!(owner: create(:user, account: account, role: :administrator))
    get "#{path}/#{run.id}", headers: headers
    expect(response.body).not_to include('Restricted CRM note')
  end

  it 'retains the result while all original source access remains valid' do
    get "#{path}/#{run.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('result', 'summary')).to eq('Restricted CRM note')
  end

  it 'hides analysis CRM sources after a restrictive native CustomRole is assigned' do
    role = create(:custom_role, account: account, permissions: ['conversation_manage'])
    account.account_users.find_by!(user_id: user.id).update!(custom_role: role)
    get "#{path}/#{run.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('Restricted CRM note')
    expect(response.parsed_body['error_code']).to eq('source_access_revoked')
  end
end
