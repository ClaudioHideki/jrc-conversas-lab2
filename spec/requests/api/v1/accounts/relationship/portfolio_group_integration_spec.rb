require 'rails_helper'

RSpec.describe 'Native relationship named portfolio integration', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship" }
  let(:group) { JrcRelationship::PortfolioGroup.create!(account: account, owner: actor, name: 'Synthetic linked portfolio') }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'filters real lists and dashboard counts by active group links without multiplying customers or changing native responsibilities' do
    other = JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account))
    second = JrcRelationship::PortfolioGroup.create!(account: account, owner: actor, name: 'Synthetic overlapping portfolio')
    [group, second].each do |portfolio|
      JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: portfolio, assignment: assignment)
    end
    JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: group, assignment: other, active: false)
    original = assignment.reload.attributes
    get "#{base}/portfolio", headers: headers, params: { portfolio_group_id: group.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([assignment.id])
    expect(response.headers['Cache-Control']).to include('no-store')
    get "#{base}/dashboard", headers: headers, params: { portfolio_group_id: group.id }
    expect(response.parsed_body.fetch('customers')).to eq(1)
    get "#{base}/dashboard", headers: headers
    expect(response.parsed_body.fetch('customers')).to eq(2)
    expect(assignment.reload.attributes).to eq(original)
  end

  it 'keeps grouped list pagination bounded and restores the native list when the filter is removed' do
    allocations = Array.new(26) do
      JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account))
    end
    allocations.each do |row|
      JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: group, assignment: row)
    end
    assignment
    get "#{base}/portfolio", headers: headers, params: { portfolio_group_id: group.id, page: 2 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').size).to eq(1)
    expect(response.parsed_body.fetch('meta')).to include('page' => 2, 'per_page' => 25, 'total' => 26)
    get "#{base}/portfolio", headers: headers
    expect(response.parsed_body.fetch('meta').fetch('total')).to eq(27)
  end

  it 'does not grant a customer through a shared group and hides all workload when any member is outside native access' do
    group.update!(visibility: 'account')
    JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: group, assignment: assignment)
    viewer = create(:user, account: account, role: :agent)
    get "#{base}/portfolio", headers: viewer.create_new_auth_token, params: { portfolio_group_id: group.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload')).to eq([])
    get "#{base}/portfolio_groups/#{group.id}/workload", headers: viewer.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('state' => 'scope_denied', 'read_only' => true, 'measures' => [])
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.body).not_to include(assignment.label)
  end

  it 'denies private or foreign group filters even if the actor could otherwise view native customers' do
    assignment
    other = create(:user, account: account, role: :agent)
    group.update!(owner: other)
    viewer = create(:user, account: account, role: :agent)
    get "#{base}/dashboard", headers: viewer.create_new_auth_token, params: { portfolio_group_id: group.id }
    expect(response).to have_http_status(:not_found)
    foreign = create(:account)
    foreign_owner = create(:user, account: foreign, role: :administrator)
    foreign_group = JrcRelationship::PortfolioGroup.create!(account: foreign, owner: foreign_owner, name: 'Foreign grouping')
    get "#{base}/portfolio", headers: headers, params: { portfolio_group_id: foreign_group.id, account_id: foreign.id }
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(foreign_group.name)
  end

  it 'projects explicit native points and hours once per customer using the existing active workload statuses' do
    assignment.update!(settings: { 'capacity_workload' => { 'hours' => 3,
                                                            'points' => { 'base' => 2, 'complexity_factor' => 3, 'risk_factor' => 2,
                                                                          'journey_factor' => 1, 'activity_effort' => 4 } } })
    inactive = JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account), status: 'inactive')
    [assignment, inactive].each do |row|
      JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: group, assignment: row)
    end
    before = [JrcRelationship::Assignment.count, JrcCrm::AuditEvent.count, JrcRelationship::HealthSnapshot.count]
    get "#{base}/portfolio_groups/#{group.id}/workload", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('state' => 'observed', 'read_only' => true, 'load_statuses' => %w[onboarding active at_risk])
    expect(response.parsed_body.fetch('measures')).to eq([
                                                           { 'unit' => 'customers', 'state' => 'available', 'value' => 1 },
                                                           { 'unit' => 'points', 'state' => 'available', 'value' => 16.0 },
                                                           { 'unit' => 'hours', 'state' => 'available', 'value' => 3.0 }
                                                         ])
    expect([JrcRelationship::Assignment.count, JrcCrm::AuditEvent.count, JrcRelationship::HealthSnapshot.count]).to eq(before)
  end

  it 'reports missing explicit points and hours as unavailable instead of inventing weights or spare capacity' do
    JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: group, assignment: assignment)
    get "#{base}/portfolio_groups/#{group.id}/workload", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('measures')).to include(
      { 'unit' => 'customers', 'state' => 'available', 'value' => 1 },
      { 'unit' => 'points', 'state' => 'explicit_inputs_missing', 'value' => nil },
      { 'unit' => 'hours', 'state' => 'explicit_inputs_missing', 'value' => nil }
    )
  end

  it 'keeps native action lists inside the same linked customer cohort' do
    other = JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account))
    JrcRelationship::PortfolioGroupAssignment.create!(account: account, portfolio_group: group, assignment: assignment)
    actions = [assignment, other].map do |row|
      JrcRelationship::Action.create!(account: account, assignment: row, owner: actor, kind: 'task',
                                      reason: 'Synthetic grouped task', source_key: SecureRandom.uuid)
    end
    get "#{base}/records/actions", headers: headers, params: { portfolio_group_id: group.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([actions.first.id])
  end

  it 'projects one thousand actual linked customers with bounded SQL and native explicit hours' do
    contacts = Contact.create!(Array.new(1000) do |index|
      { account: account, name: "Synthetic grouped scale customer #{index}" }
    end)
    allocations = JrcRelationship::Assignment.create!(contacts.map do |contact|
      { account: account, owner: actor, contact: contact, status: 'active', settings: { 'capacity_workload' => { 'hours' => 2 } } }
    end)
    JrcRelationship::PortfolioGroupAssignment.create!(allocations.map do |row|
      { account: account, portfolio_group: group, assignment: row, active: true }
    end)
    queries = []
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    subscriber = ->(_name, _start, _finish, _id, payload) { queries << payload[:name] unless payload[:name] == 'SCHEMA' }
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      get "#{base}/portfolio_groups/#{group.id}/workload", headers: headers
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('measures')).to include(
      { 'unit' => 'customers', 'state' => 'available', 'value' => 1000 },
      { 'unit' => 'hours', 'state' => 'available', 'value' => 2000.0 }
    )
    expect(queries.size).to be < 200
    puts({ named_portfolio_scale: { customers: 1000, queries: queries.size, elapsed_seconds: elapsed.round(4), real_database: true } }.to_json)
  end

  [false, ['1'], { id: 1 }].each do |value|
    it "rejects malformed group filter #{value.inspect} rather than silently expanding the list" do
      get "#{base}/portfolio", headers: headers, params: { portfolio_group_id: value }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).not_to have_key('payload')
    end
  end
end
