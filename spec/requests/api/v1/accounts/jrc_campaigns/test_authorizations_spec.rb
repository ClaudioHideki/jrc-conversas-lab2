require 'rails_helper'

RSpec.describe 'Single test authorizations', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account, channel: create(:channel_api, account: account, webhook_url: 'https://evolution.example.test/chatwoot/webhook/demo')) }
  let(:configuration) do
    { account_id: account.id, inbox_id: inbox.id, base_url: 'https://evolution.example.test', instance: 'demo',
      sender_number: '551155550000', api_key_env: 'JRC_CAMPAIGNS_EVOLUTION_DEMO_API_KEY' }
  end
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_campaigns/test_authorizations" }
  let(:payload) do
    { test_authorization: { inbox_id: inbox.id, phone_number: '5511999999000', evidence: 'Holder confirmed one test in synthetic QA chat.', operator_confirmed: true } }
  end
  let(:authorization) do
    JrcCampaigns::TestAuthorization.create!(account: account, inbox: inbox, recorded_by: admin, phone_number: '+5511999999000',
                                            evidence: 'QA only', granted_at: Time.current,
                                            connector_snapshot: JrcCampaigns::EvolutionConnector.for(inbox).public_configuration.slice(*JrcCampaigns::TestAuthorization::IDENTITY_FIELDS))
  end

  around do |example|
    with_modified_env('JRC_CAMPAIGNS_EVOLUTION_CONNECTORS' => [configuration].to_json) { example.run }
  end

  before { account.enable_features!('jrc_campaigns') }

  it 'records narrowly scoped evidence without creating or updating campaign consent or sending' do
    historical = JrcCampaigns::Consent.create!(account: account, recorded_by: admin, phone_number: '+5511999999000',
                                               evidence: 'Historical evidence unchanged', granted_at: 1.day.ago)
    expect do
      post base, headers: admin.create_new_auth_token, params: payload, as: :json
    end.to change(JrcCampaigns::TestAuthorization, :count).by(1).and change(JrcCampaigns::Consent, :count).by(0)
    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include('sender_number' => configuration[:sender_number], 'phone_number' => '+5511999999000', 'consumed_at' => nil)
    expect(historical.reload).to have_attributes(purpose: nil, evidence: 'Historical evidence unchanged')
    expect(JrcCampaigns::TestDelivery.where(account: account)).to be_empty
  end

  it 'requires explicit operator confirmation' do
    payload[:test_authorization][:operator_confirmed] = false
    post base, headers: admin.create_new_auth_token, params: payload, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcCampaigns::TestAuthorization.where(account: account)).to be_empty
  end

  it 'rejects blank evidence and malformed destinations' do
    payload[:test_authorization].merge!(evidence: '', phone_number: 'invalid')
    post base, headers: admin.create_new_auth_token, params: payload, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'does not create two available grants for the same route' do
    authorization
    post base, headers: admin.create_new_auth_token, params: payload, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcCampaigns::TestAuthorization.where(account: account).count).to eq(1)
  end

  it 'does not permit changing evidence or clearing consumption through creation parameters' do
    payload[:test_authorization].merge!(recorded_by_id: 0, consumed_at: Time.current, granted_at: 1.year.ago, connector_snapshot: {})
    post base, headers: admin.create_new_auth_token, params: payload, as: :json
    expect(response).to have_http_status(:created)
    expect(JrcCampaigns::TestAuthorization.where(account: account).sole).to have_attributes(recorded_by: admin, consumed_at: nil)
  end

  it 'scopes history and revocation to the current account' do
    authorization
    other = create(:account)
    other.enable_features!('jrc_campaigns')
    other_admin = create(:user, account: other, role: :administrator)
    foreign_base = "/api/v1/accounts/#{other.id}/jrc_campaigns/test_authorizations"
    get foreign_base, headers: other_admin.create_new_auth_token
    expect(response.parsed_body).to eq([])
    delete "#{foreign_base}/#{authorization.id}", headers: other_admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    expect(authorization.reload.revoked_at).to be_nil
    foreign_payload = { test_authorization: payload[:test_authorization].merge(inbox_id: inbox.id) }
    post foreign_base, headers: other_admin.create_new_auth_token, params: foreign_payload, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'denies regular agents and disabled accounts' do
    agent = create(:user, account: account, role: :agent)
    get base, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
    post base, headers: agent.create_new_auth_token, params: payload, as: :json
    expect(response).to have_http_status(:forbidden)
    account.disable_features!('jrc_campaigns')
    get base, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
  end

  it 'revokes while retaining the original evidence and grant date' do
    original = authorization.attributes.slice('evidence', 'granted_at', 'recorded_by_id')
    delete "#{base}/#{authorization.id}", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:no_content)
    expect(authorization.reload.revoked_at).to be_present
    expect(authorization.attributes.slice('evidence', 'granted_at', 'recorded_by_id')).to eq(original)
  end

  it 'does not authorize an arbitrary API inbox' do
    with_modified_env('JRC_CAMPAIGNS_EVOLUTION_CONNECTORS' => '[]') do
      post base, headers: admin.create_new_auth_token, params: payload, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
