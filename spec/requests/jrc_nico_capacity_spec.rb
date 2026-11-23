require 'rails_helper'

RSpec.describe 'Account-owned NICO capacity diagnostics', type: :request do
  let(:account) { create(:account, custom_attributes: { nico_enabled: true, nico_monthly_token_limit: 2_000_000 }) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:headers) { user.create_new_auth_token }

  it 'keeps operational capacity in Quick and exposes only confirmed consumption in AI usage' do
    get "/api/v1/accounts/#{account.id}/jrc_nico/operations", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['capacity']).to include('token_limit' => 2_000_000, 'remaining_tokens' => 2_000_000)
    get "/api/v1/accounts/#{account.id}/jrc_ai/usage", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).not_to have_key('nico_capacity')
    expect(response.parsed_body.fetch('totals')).to include('total_tokens' => 0, 'executions' => 0)
    expect(response.body).not_to include('api_key', 'service_token')
  end

  it 'rejects another account diagnostics using the existing membership policy' do
    other = create(:account)
    get "/api/v1/accounts/#{other.id}/jrc_nico/operations", headers: headers
    expect(response).to have_http_status(:unauthorized)
    get "/api/v1/accounts/#{other.id}/jrc_ai/usage", headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('nico_capacity', 'token_limit')
  end

  it 'keeps detailed AI usage restricted to administrators' do
    agent = create(:user, account: account, role: :agent)
    get "/api/v1/accounts/#{account.id}/jrc_ai/usage", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('nico_capacity')
  end
end
