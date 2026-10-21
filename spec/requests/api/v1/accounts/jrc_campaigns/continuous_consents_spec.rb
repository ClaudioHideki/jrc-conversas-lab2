require 'rails_helper'

RSpec.describe 'Continuous campaign consent', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_campaigns/consents" }
  let(:phone) { '+5511999999000' }
  let(:payload) do
    { consent: { phone_number: phone, evidence: 'Synthetic holder authorized recurring WhatsApp tests and campaigns until revocation.', operator_confirmed: true } }
  end
  let(:historical) do
    JrcCampaigns::Consent.create!(account: account, recorded_by: admin, phone_number: phone, evidence: 'Original evidence with unconfirmed scope',
                                 granted_at: 2.days.ago)
  end

  before { account.enable_features!('jrc_campaigns') }

  it 'records explicit continuous permission that remains eligible across reads without sending' do
    post base, headers: admin.create_new_auth_token, params: payload, as: :json
    expect(response).to have_http_status(:created)
    consent = JrcCampaigns::Consent.find(response.parsed_body['id'])
    expect(consent).to have_attributes(account: account, recorded_by: admin, purpose: 'whatsapp_campaigns', revoked_at: nil)
    2.times { expect(JrcCampaigns::EligibilityPolicy.new(account: account, phone_number: phone, purpose: 'whatsapp_campaigns').rejection_reason).to be_nil }
    expect(JrcCampaigns::TestDelivery.where(account: account)).to be_empty
  end

  it 'requires the operator to confirm the recurring purpose' do
    payload[:consent].delete(:operator_confirmed)
    post base, headers: admin.create_new_auth_token, params: payload, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcCampaigns::Consent.where(account: account)).to be_empty
  end

  it 'rejects malformed numbers and empty evidence' do
    payload[:consent].merge!(phone_number: 'invalid', evidence: '')
    post base, headers: admin.create_new_auth_token, params: payload, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcCampaigns::Consent.where(account: account)).to be_empty
  end

  it 'never silently broadens historical consent for an existing phone' do
    original = historical.attributes
    post base, headers: admin.create_new_auth_token, params: payload, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(historical.reload.attributes).to eq(original)
  end

  it 'creates a linked new grant from explicit fresh evidence while preserving historical fields' do
    original = historical.attributes.slice('evidence', 'granted_at', 'recorded_by_id', 'purpose')
    payload[:consent][:supersedes_id] = historical.id
    post base, headers: admin.create_new_auth_token, params: payload, as: :json
    expect(response).to have_http_status(:created)
    renewed = JrcCampaigns::Consent.find(response.parsed_body['id'])
    expect(renewed).to have_attributes(supersedes_id: historical.id, purpose: 'whatsapp_campaigns', revoked_at: nil)
    expect(historical.reload.attributes.slice('evidence', 'granted_at', 'recorded_by_id', 'purpose')).to eq(original)
    expect(historical.revoked_at).to be_present
    expect(renewed.evidence).to eq(payload[:consent][:evidence])
    get base, headers: admin.create_new_auth_token
    expect(response.parsed_body.find { |entry| entry['id'] == historical.id }['superseded_by_id']).to eq(renewed.id)
  end

  it 'rolls back closing the old grant if the new evidence is invalid' do
    original = historical.attributes
    payload[:consent].merge!(supersedes_id: historical.id, evidence: '')
    post base, headers: admin.create_new_auth_token, params: payload, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(historical.reload.attributes).to eq(original)
    expect(JrcCampaigns::Consent.where(account: account).count).to eq(1)
  end

  it 'does not replace active continuous permission on repeated registration' do
    post base, headers: admin.create_new_auth_token, params: payload, as: :json
    first = JrcCampaigns::Consent.find(response.parsed_body['id'])
    original = first.attributes
    payload[:consent][:supersedes_id] = first.id
    post base, headers: admin.create_new_auth_token, params: payload, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(first.reload.attributes).to eq(original)
    expect(JrcCampaigns::Consent.where(account: account).count).to eq(1)
  end

  it 'does not use a stale previous ID or another account record' do
    foreign_account = create(:account)
    foreign = JrcCampaigns::Consent.create!(account: foreign_account, recorded_by: admin, phone_number: phone,
                                           evidence: 'Private other-account evidence', granted_at: Time.current)
    payload[:consent][:supersedes_id] = foreign.id
    post base, headers: admin.create_new_auth_token, params: payload, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(foreign.reload.revoked_at).to be_nil
    get base, headers: admin.create_new_auth_token
    expect(response.parsed_body).to eq([])
  end

  it 'does not accept a previous record for a different phone in the same account' do
    payload[:consent].merge!(supersedes_id: historical.id, phone_number: '+5511999999001')
    post base, headers: admin.create_new_auth_token, params: payload, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(historical.reload.revoked_at).to be_nil
  end

  it 'revokes continuously granted permission and preserves the original revocation date on retries' do
    post base, headers: admin.create_new_auth_token, params: payload, as: :json
    consent = JrcCampaigns::Consent.find(response.parsed_body['id'])
    delete "#{base}/#{consent.id}", headers: admin.create_new_auth_token
    first_revocation = consent.reload.revoked_at
    travel 1.minute do
      delete "#{base}/#{consent.id}", headers: admin.create_new_auth_token
      expect(response).to have_http_status(:no_content)
      expect(consent.reload.revoked_at).to eq(first_revocation)
    end
    expect(JrcCampaigns::EligibilityPolicy.new(account: account, phone_number: phone, purpose: 'whatsapp_campaigns').rejection_reason).to match(/revogado/)
  end

  it 'does not allow agents to register or confirm consent' do
    agent = create(:user, account: account, role: :agent)
    payload[:consent][:supersedes_id] = historical.id
    post base, headers: agent.create_new_auth_token, params: payload, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(historical.reload.revoked_at).to be_nil
  end
end
