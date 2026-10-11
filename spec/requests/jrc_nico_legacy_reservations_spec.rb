require 'rails_helper'

RSpec.describe 'Administrative legacy NICO reservation review', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:headers) { user.create_new_auth_token }
  let(:record) { JrcNico::Inference.create!(account: account, user: user, status: 'unknown', reserved_tokens: 1000, created_at: 1.hour.ago) }
  let(:url) { "/api/v1/accounts/#{account.id}/jrc_ai/legacy_reservations" }
  let(:decision) do
    report = JrcNico::LegacyReservations.new(member: account.account_users.find_by!(user: user))
    { request_id: SecureRandom.uuid, fingerprint: report.describe(record, 'inference')[:fingerprint], classification: 'unknown',
      source: 'investigation', justification: 'Reviewed available evidence and retained the unknown reservation.', excluded_usage_event_ids: [],
      evidence: [{ reference: 'local-evidence', sha256: Digest::SHA256.hexdigest('sanitized local evidence') }] }
  end

  it 'returns only account-owned legacy rows and a read-only monthly summary' do
    record
    get url, headers: headers, params: { period: record.created_at.strftime('%Y-%m') }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('account_id' => account.id, 'dry_run' => true, 'count' => 1, 'legacy_reserved_tokens' => 1000)
    expect(response.body).not_to include('api_key', 'service_token')
    expect(record.reload.reserved_tokens).to eq(1000)
  end

  it 'requires a valid month and does not expose internal exceptions' do
    get url, headers: headers, params: { period: 'invalid' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'invalid_legacy_review')
  end

  it 'rejects agents for reports, simulations and applications' do
    agent = create(:user, account: account, role: :agent)
    auth = agent.create_new_auth_token
    get url, headers: auth, params: { period: Time.current.strftime('%Y-%m') }
    expect(response).to have_http_status(:unauthorized)
    post "#{url}/inference/#{record.id}/simulate", headers: auth, params: { decision: decision }, as: :json
    expect(response).to have_http_status(:unauthorized)
    post "#{url}/inference/#{record.id}/reconcile", headers: auth, params: { decision: decision, authorized: true }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(record.reload.accounting).to eq({})
  end

  it 'rejects another account even for an administrator' do
    other = create(:account)
    get "/api/v1/accounts/#{other.id}/jrc_ai/legacy_reservations", headers: headers, params: { period: Time.current.strftime('%Y-%m') }
    expect(response).to have_http_status(:unauthorized)
    other_user = create(:user, account: other)
    foreign = JrcNico::Inference.create!(account: other, user: other_user, reserved_tokens: 1000)
    post "#{url}/inference/#{foreign.id}/simulate", headers: headers, params: { decision: decision }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('reserved_tokens', 'fingerprint')
  end

  it 'keeps simulation read-only and requires a boolean explicit authorization to apply' do
    input = decision
    post "#{url}/inference/#{record.id}/simulate", headers: headers, params: { decision: input }, as: :json
    expect(response).to have_http_status(:ok)
    token = response.parsed_body.fetch('simulation_token')
    expect(record.reload.accounting).to eq({})
    post "#{url}/inference/#{record.id}/reconcile", headers: headers,
                                               params: { decision: input, authorized: 'true', simulation_token: token }, as: :json
    expect(response).to have_http_status(:unauthorized)
    post "#{url}/inference/#{record.id}/reconcile", headers: headers,
                                               params: { decision: input, authorized: true, simulation_token: token }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('dry_run' => false, 'classification' => 'unknown', 'resulting_reserved_tokens' => 1000)
    expect(record.reload.accounting['legacy_reviews'].size).to eq(1)
  end

  it 'returns a sanitized conflict when no prior simulation was supplied' do
    post "#{url}/inference/#{record.id}/reconcile", headers: headers, params: { decision: decision, authorized: true }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['error']).to eq('legacy_review_conflict')
    expect(record.reload.reserved_tokens).to eq(1000)
  end
end
