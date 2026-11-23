require 'rails_helper'

RSpec.describe 'AI usage accounting provenance', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }

  it 'reconciles confirmed, estimated and unclassified records without borrowing another account usage' do
    JrcAi::UsageEvent.create!(account: account, agent_key: 'nico', feature: 'nico_operator', input_tokens: 7, output_tokens: 3,
                             total_tokens: 10, metadata: { usage_estimated: false, cost_available: false })
    JrcAi::UsageEvent.create!(account: account, agent_key: 'nico', feature: 'nico_operator', input_tokens: 3, output_tokens: 2,
                             total_tokens: 5, metadata: { usage_estimated: true, cost_available: false })
    JrcAi::UsageEvent.create!(account: account, agent_key: 'nico', feature: 'nico_operator', input_tokens: 2, output_tokens: 2,
                             total_tokens: 4, metadata: {})
    JrcAi::UsageEvent.create!(account: create(:account), agent_key: 'nico', feature: 'nico_operator', input_tokens: 999,
                             output_tokens: 0, total_tokens: 999, metadata: { usage_estimated: false })

    get "/api/v1/accounts/#{account.id}/jrc_ai/usage", headers: user.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('totals')).to include('total_tokens' => 19, 'confirmed_tokens' => 10,
                                                           'estimated_tokens' => 5, 'unclassified_tokens' => 4,
                                                           'estimated_cost_cents' => nil)
    expect(response.parsed_body.fetch('recent').map { |row| row['usage_basis'] }.sort)
      .to eq(%w[confirmed estimated unclassified])
  end
end
