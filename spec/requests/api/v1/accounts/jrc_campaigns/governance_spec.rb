require 'rails_helper'

RSpec.describe 'Campaign governance', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:campaign) { JrcCampaigns::Campaign.create!(account: account, name: 'Pilot') }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_campaigns" }

  before { account.enable_features!('jrc_campaigns') }

  it 'rejects agent campaign listing' do
    get "#{base}/campaigns", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
  end

  it 'rejects agent launch and export' do
    post "#{base}/campaigns/#{campaign.id}/launch", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
    get "#{base}/campaigns/#{campaign.id}/export", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
  end

  it 'rejects agent test sends before calling a provider' do
    post "#{base}/campaigns/test_message", headers: agent.create_new_auth_token, params: {}, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'does not expose another account campaign' do
    other = JrcCampaigns::Campaign.create!(account: create(:account), name: 'Private')
    get "#{base}/campaigns/#{other.id}", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'requires a matching reviewed digest for explicit approval' do
    post "#{base}/campaigns/#{campaign.id}/request_review", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:success)
    digest = response.parsed_body.fetch('review_digest')
    post "#{base}/campaigns/#{campaign.id}/approve", headers: admin.create_new_auth_token, params: { digest: 'stale' }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post "#{base}/campaigns/#{campaign.id}/approve", headers: admin.create_new_auth_token, params: { digest: digest }, as: :json
    expect(response).to have_http_status(:success)
    expect(response.parsed_body.fetch('approved_by_id')).to eq(admin.id)
  end

  it 'records consent evidence and revokes it within the account' do
    post "#{base}/consents", headers: admin.create_new_auth_token,
                             params: { consent: { phone_number: '+5511999999999', evidence: 'Customer form 2026-09-07', operator_confirmed: true } }, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch('id')
    delete "#{base}/consents/#{id}", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:no_content)
    expect(JrcCampaigns::Consent.find(id).revoked_at).to be_present
  end
end
