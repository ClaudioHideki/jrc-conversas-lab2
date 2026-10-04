require 'rails_helper'

RSpec.describe 'CRM actionable goal insights', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:pipeline) { create(:jrc_crm_pipeline, account: account) }
  let(:stage) { create(:jrc_crm_stage, account: account, pipeline: pipeline) }
  let(:contact) { create(:contact, account: account) }
  let(:deal) do
    create(:jrc_crm_deal, account: account, owner: admin, pipeline: pipeline, stage: stage,
           contact: contact, status: 'open', value_cents: 50_000, probability: 50)
  end
  let(:url) { "/api/v1/accounts/#{account.id}/crm/goals/dashboard" }

  before { account.enable_features!('jrc_crm') }

  it 'calculates pipeline and forecast coverage and links recommendations to real CRM records without writing data' do
    JrcCrm::SalesGoal.create!(account: account, name: 'Revenue goal', status: 'active', scope_kind: 'company',
                             metric: 'revenue', period_start: Time.zone.today.beginning_of_month,
                             period_end: Time.zone.today.end_of_month, target_cents: 100_000,
                             allocations: [{ user_id: admin.id, target_cents: 100_000 }])
    proposal = create(:jrc_crm_proposal, account: account, owner: admin, deal: deal, status: 'sent',
                       sent_at: 5.days.ago, follow_up_days: 1)
    before_counts = [JrcCrm::Activity.count, JrcCrm::SalesOrder.count, JrcCrm::Contract.count]

    get url, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    data = response.parsed_body
    expect(data.slice('pipeline_coverage_percent', 'forecast_coverage_percent')).to eq(
      'pipeline_coverage_percent' => 50.0, 'forecast_coverage_percent' => 25.0
    )
    seller = data.fetch('ranking').find { |row| row['user_id'] == admin.id }
    expect(seller).to include('target_cents' => 100_000, 'forecast_cents' => 25_000, 'below_pace' => true)
    actions = data.fetch('next_actions').index_by { |row| row.fetch('key') }
    expect(actions.keys).to include('goal_gap', 'pipeline_coverage', 'sellers_below_pace', 'stale_deals', 'proposals_waiting')
    expect(actions.fetch('stale_deals').fetch('deal_ids')).to include(deal.id)
    expect(actions.fetch('proposals_waiting').fetch('records').map { |row| row.fetch('id') }).to include(proposal.id)
    expect(actions.values).to all(include('reason', 'priority', 'records', 'nico_prompt'))
    expect([JrcCrm::Activity.count, JrcCrm::SalesOrder.count, JrcCrm::Contract.count]).to eq(before_counts)
  end

  it 'returns zero coverage rather than non-finite values when there is no monetary target' do
    deal
    get url, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.slice('pipeline_coverage_percent', 'forecast_coverage_percent')).to eq(
      'pipeline_coverage_percent' => 0, 'forecast_coverage_percent' => 0
    )
  end
end
