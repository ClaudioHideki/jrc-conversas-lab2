require 'rails_helper'

RSpec.describe 'Relationship portfolio authorization', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { agent.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/relationship" }
  let!(:own) { JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account), owner: agent) }
  let!(:other) { JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account), owner: admin) }
  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'CS-01 exposes only the analyst portfolio in both rows and counts' do
    get "#{url}/portfolio", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload'].pluck('id')).to eq([own.id])
    expect(response.parsed_body.dig('meta', 'total')).to eq(1)
  end

  it 'CS-10 blocks unauthorized portfolio detail and writes' do
    get "#{url}/portfolio/#{other.id}", headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    patch "#{url}/portfolio/#{other.id}", params: { assignment: { owner_id: agent.id } }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(other.reload.owner).to eq(admin)
  end

  it 'CS-08 changes responsible without creating another portfolio identity' do
    patch "#{url}/portfolio/#{own.id}", params: { assignment: { owner_id: admin.id } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(own.reload.owner).to eq(admin)
    expect(JrcRelationship::Assignment.where(account: account, contact_id: own.contact_id).count).to eq(1)
    get "#{url}/portfolio", headers: headers, as: :json
    expect(response.parsed_body['payload']).to eq([])
  end

  it 'does not grant team management or configuration to a standard analyst' do
    get "#{url}/team", headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    get "#{url}/configuration", headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'blocks the whole module with its native feature disabled' do
    account.disable_features!('jrc_relationship')
    get "#{url}/portfolio", headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'rolls back a bulk operation containing an unauthorized customer instead of transferring the allowed subset' do
    post "#{url}/portfolio/batch", params: { ids: [own.id, other.id], operation: 'assign', owner_id: agent.id, request_id: SecureRandom.uuid }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(own.reload.owner).to eq(agent)
    expect(other.reload.owner).to eq(admin)
  end

  it 'does not expose administrative history export to an analyst' do
    get "#{url}/export_history", headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'calculates daily NPS from promoters minus detractors, with native CSAT and no foreign account responses' do
    survey = JrcRelationship::Survey.create!(account: account, assignment: own, owner: agent, kind: 'nps',
      token_digest: Digest::SHA256.hexdigest(SecureRandom.hex), expires_at: 30.days.from_now, score: 3, responded_at: Time.current)
    conversation = create(:conversation, account: account, contact: own.contact)
    message = create(:message, account: account, conversation: conversation, content_type: :input_csat)
    create(:csat_survey_response, account: account, contact: own.contact, conversation: conversation, message: message, rating: 4)
    create(:csat_survey_response, rating: 1)
    get "#{url}/dashboard", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['nps']).to eq(-100)
    expect(response.parsed_body['nps_evolution'].last['score']).to eq(-100)
    expect(response.parsed_body['csat_evolution'].last['score']).to eq(4)
    expect(survey.reload.score).to eq(3)
  end
end
