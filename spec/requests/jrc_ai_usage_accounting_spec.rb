require 'rails_helper'

RSpec.describe 'AI usage accounting provenance', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }

  it 'shows only provider-confirmed tokens across totals, groups and records while preserving the audit' do
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
    body = response.parsed_body
    expect(body.fetch('totals')).to eq('total_tokens' => 10, 'input_tokens' => 7, 'output_tokens' => 3,
                                     'tokens_today' => 10, 'executions' => 1)
    expect(body.fetch('recent').map { |row| row.fetch('total_tokens') }).to eq([10])
    %w[by_agent by_model by_user].each do |group|
      expect(body.fetch(group).sum { |row| row.fetch('tokens') }).to eq(10)
    end
    expect(body).not_to have_key('nico_capacity')
    expect(body.fetch('recent').first).not_to have_key('estimated_cost_cents')
    expect(account.jrc_ai_usage_events.count).to eq(3)
  end
end
