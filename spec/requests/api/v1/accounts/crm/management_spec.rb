require 'rails_helper'

RSpec.describe 'CRM management route', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/management" }

  before { account.enable_features!('jrc_crm') }

  it 'preserves the existing administrator-only restriction' do
    get url, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns the existing metrics contract for an administrator' do
    account.account_users.find_by!(user: agent).update!(role: :administrator)
    get url, params: { start_date: '2026-09-01', end_date: '2026-09-25' }, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.first.fetch('metrics')).to include('open_deals_count', 'closed_won_count', 'won_revenue_cents')
  end
end
