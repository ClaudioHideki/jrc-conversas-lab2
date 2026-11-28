require 'rails_helper'

RSpec.describe 'CRM funnel report', type: :request do
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:pipeline) { create(:jrc_crm_pipeline, account: account) }
  let(:first_stage) { create(:jrc_crm_stage, account: account, pipeline: pipeline) }
  let(:later_stage) { create(:jrc_crm_stage, account: account, pipeline: pipeline) }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/funnel" }

  before { account.enable_features!('jrc_crm') }

  it 'returns authorized cohort rows and stage movements in both native and imported formats' do
    company = account.master_companies.create!(name: 'Authorized customer')
    deal = create(:jrc_crm_deal, account: account, owner: agent, pipeline: pipeline, stage: later_stage, company_id: company.id,
                  created_at: Time.utc(2026, 11, 1, 3), description: 'PRIVATE_DESCRIPTION')
    older = create(:jrc_crm_deal, account: account, owner: agent, pipeline: pipeline, stage: first_stage,
                   created_at: Time.utc(2026, 11, 1, 2, 59))
    colleague = create(:user, account: account, role: :agent)
    private_deal = create(:jrc_crm_deal, account: account, owner: colleague, pipeline: pipeline, stage: first_stage,
                          created_at: Time.utc(2026, 11, 10))
    [
      [deal.id, first_stage.id.to_s, later_stage.id.to_s, 2],
      [deal.id, { stage_id: later_stage.id }, { stage_id: first_stage.id }, 3],
      [private_deal.id, first_stage.id.to_s, later_stage.id.to_s, 14]
    ].each do |id, from, to, day|
      account.jrc_crm_audit_events.create!(resource_type: 'JrcCrm::Deal', resource_id: id, event_type: 'deal_stage_changed',
                                           from_value: from, to_value: to, created_at: Time.utc(2026, 11, day))
    end

    headers = agent.create_new_auth_token
    get url, headers: headers, params: { month: '2026-11', pipeline_id: pipeline.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('owners').pluck('id')).to eq([agent.id])
    row = response.parsed_body.fetch('deals').sole
    expect(row).to include('id' => deal.id, 'stage_id' => later_stage.id, 'company_name' => nil)
    expect(row.fetch('moves').pluck('to')).to eq([later_stage.id, first_stage.id])
    expect(response.body).not_to include('PRIVATE_DESCRIPTION')

    account.enable_features!('jrc_customer_master')
    get url, headers: headers, params: { month: '2026-11', pipeline_id: pipeline.id }
    expect(response.parsed_body.fetch('deals').sole.fetch('company_name')).to eq(company.name)

    get url, headers: headers, params: { month: '2026-11', pipeline_id: pipeline.id, mode: 'portfolio' }
    expect(response.parsed_body.fetch('deals').pluck('id')).to contain_exactly(deal.id, older.id)

    get url, headers: headers, params: { month: '2026-99' }
    expect(response).to have_http_status(:bad_request)
  end
end
