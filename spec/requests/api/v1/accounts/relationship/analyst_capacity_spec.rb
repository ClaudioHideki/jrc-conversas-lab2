require 'rails_helper'

RSpec.describe 'Native current analyst capacity', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:analyst) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/team/#{analyst.id}/capacity" }
  let(:team) { create(:team, account: account) }
  let(:workloads) do
    [2, 3].zip([1.5, 2.25]).map do |base, hours|
      { capacity_workload: { points: { base: base, complexity_factor: 1, risk_factor: 1, journey_factor: 1, activity_effort: 0 }, hours: hours } }
    end
  end
  let(:allocations) do
    workloads.map do |settings|
      JrcRelationship::Assignment.create!(account: account, owner: analyst, team: team, contact: create(:contact, account: account),
                                          settings: settings)
    end
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'pages real point/hour scopes separately and exposes the existing overload without a fake incoming proposal or mutation' do
    allocations
    JrcRelationship::Configuration.create!(account: account, rules: { portfolio_capacity_limits: [
                                             { user_id: analyst.id, unit: 'points', maximum: 10, availability: 0.8, dedication: 0.5 }
                                           ] })
    JrcRelationship::Configuration.create!(account: account, scope_key: "team:#{team.id}", rules: { portfolio_capacity_limits: [
                                             { user_id: analyst.id, unit: 'hours', maximum: 8, availability: 1, dedication: 1 }
                                           ] })
    before = allocations.map(&:attributes)
    get url, headers: headers, params: { page: 1, per_page: 1 }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('meta')).to eq('page' => 1, 'per_page' => 1, 'total' => 2)
    expect(response.parsed_body.fetch('payload').first).to include('unit' => 'points', 'current' => 5, 'effective_capacity' => 4,
                                                                   'available_after' => -1)
    get url, headers: headers, params: { page: 2, per_page: 1 }
    expect(response.parsed_body.fetch('payload').first).to include('unit' => 'hours', 'current' => 3.75, 'effective_capacity' => 8)
    expect(response.body).not_to include('baseline_digest', 'incoming', 'projected')
    expect(allocations.map { |row| row.reload.attributes }).to eq(before)
  end

  it 'does not turn missing explicit hour measurements into zero free workload' do
    JrcRelationship::Assignment.create!(account: account, owner: analyst, contact: create(:contact, account: account))
    JrcRelationship::Configuration.create!(account: account, rules: { portfolio_capacity_limits: [
                                             { user_id: analyst.id, unit: 'hours', maximum: 8, availability: 1, dedication: 1 }
                                           ] })
    get url, headers: headers
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('payload').first).to include('blocker' => 'capacity_workload_missing', 'unit' => 'hours')
    expect(response.parsed_body.fetch('payload').first).not_to have_key('current')
  end

  it 'reports a genuine zero active load from the actual account rule when the analyst has no active allocations' do
    JrcRelationship::Configuration.create!(account: account, rules: { portfolio_capacity_limits: [
                                             { user_id: analyst.id, maximum: 10, availability: 1, dedication: 1 }
                                           ] })
    get url, headers: headers
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('payload').first).to include('unit' => 'customers', 'current' => 0, 'effective_capacity' => 10)
    expect(response.parsed_body.fetch('read_only')).to be(true)
  end

  it 'denies hidden active unit workload before returning a partial count or capacity limit' do
    company = account.master_companies.create!(name: 'Synthetic capacity operator', relationship_type: 'internal', tax_id: '11444777000161')
    units = Array.new(2) do |index|
      account.jrc_crm_business_units.create!(name: "Synthetic capacity unit #{index}", code: SecureRandom.hex(6), company_id: company.id)
    end
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: company,
                                                business_unit: units.first, active: true, structure_managed: true)
    allocations.first.update!(business_unit: units.first)
    allocations.last.update!(business_unit: units.last)
    get url, headers: headers
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).not_to have_key('payload')
    expect(response.parsed_body).not_to have_key('analyst')
  end

  it 'preserves team permission and account isolation for the existing analyst identity' do
    reader = create(:user, account: account, role: :agent)
    get url, headers: reader.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
    foreign = create(:user, account: create(:account), role: :administrator)
    get url, headers: foreign.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).not_to have_key('payload')
  end
end
