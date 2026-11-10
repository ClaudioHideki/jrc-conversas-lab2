require 'rails_helper'

# Prepared native HTTP/PostgreSQL acceptance. NOT executed in the export environment.
# Historical facts below are explicitly synthetic, not a production backfill.
RSpec.describe 'Approved TRR historical cohort', type: :request do
  self.use_transactional_tests = false
  let(:account) { create(:account) }
  let(:manager) { create(:user, account: account, role: :administrator) }
  let(:headers) { manager.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship/retention" }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: manager)) }
  let(:mapping) { { 'eligible_statuses' => ['active'], 'contact_mode' => 'relationship_status', 'target_percent' => 90 } }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account), owner: manager, status: 'active') }
  before do
    config = ActiveRecord::Base.connection_db_config
    owned = Rails.env.test? && config.adapter == 'postgresql' && config.database == 'jrc_ag_retention_native_test'
    owned &&= ActiveRecord::Base.connection.current_database == config.database && !ActiveRecord::Base.connection.transaction_open?
    raise 'Committed TRR fixtures require their exclusive synthetic PostgreSQL database' unless owned

    account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
  end

  def configure
    JrcRelationship::Configuration.create!(account: account, scope_key: 'account', rules: { 'retention_policy' => mapping })
  end

  def observation(row, at:, status: 'active', present: true)
    facts = { 'customer_key' => "contact:#{row.contact_id}", 'customer_type' => 'contact',
      'source_present' => present, 'status' => status, 'master_active' => nil, 'registration_status' => 'registered',
      'assignment_id' => row.id, 'owner_id' => row.owner_id, 'team_id' => row.team_id,
      'business_unit_id' => row.business_unit_id, 'portfolio_ids' => [] }
    JrcRelationship::RetentionState.create!(account: account, customer_key: facts['customer_key'], assignment_id: row.id,
      owner_id: row.owner_id, team_id: row.team_id, business_unit_id: row.business_unit_id, observed_at: Time.utc(2026, 10, at, 12), facts: facts)
  end

  def historical_query
    travel_to(Time.utc(2026, 11, 2, 12)) do
      get base, headers: headers, params: { period: 'monthly', reference: '2026-10-01' }
    end
  end

  it 'does not infer the configured eligible statuses' do
    historical_query
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('available' => false, 'value' => nil, 'code' => 'configuration_required')
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'does not invent history from current native allocations' do
    configure
    assignment
    historical_query
    expect(response.parsed_body).to include('available' => false, 'code' => 'insufficient_history')
    expect(JrcRelationship::RetentionCoverage.where(account: account)).not_to exist
  end

  it 'starts the baseline only with an explicit authorized reason and replays without another baseline' do
    assignment
    post "#{base}/start", headers: headers, as: :json, params: { reason: 'Start synthetic evidence now' }
    expect(response).to have_http_status(:ok), response.body
    first = JrcRelationship::RetentionCoverage.find_by!(account: account).started_at
    count = JrcRelationship::RetentionState.where(account: account).count
    post "#{base}/start", headers: headers, as: :json, params: { reason: 'Recheck the same baseline' }
    expect(response).to have_http_status(:ok)
    expect(JrcRelationship::RetentionCoverage.find_by!(account: account).started_at).to eq(first)
    expect(JrcRelationship::RetentionState.where(account: account).count).to eq(count)
  end

  it 'denies baseline creation to an ordinary analyst without granting new rights' do
    analyst = create(:user, account: account, role: :agent)
    before = account.account_users.find_by!(user: analyst).attributes
    post "#{base}/start", headers: analyst.create_new_auth_token, as: :json, params: { reason: 'Unauthorized start' }
    expect(response).to have_http_status(:forbidden)
    expect(JrcRelationship::RetentionCoverage.where(account: account)).not_to exist
    expect(account.account_users.find_by!(user: analyst).attributes).to eq(before)
  end

  it 'uses the initial cohort and excludes later entrants, without changing native business data' do
    configure
    initial = assignment
    entrant = JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account), owner: manager, status: 'active')
    observation(initial, at: 1)
    observation(entrant, at: 10)
    JrcRelationship::RetentionCoverage.create!(account: account, started_at: Time.utc(2026, 9, 30))
    counts = [JrcRelationship::Assignment.count, JrcRelationship::RetentionState.count, JrcCrm::AuditEvent.count]
    travel_to(Time.utc(2026, 11, 2)) do
      get base, headers: headers, params: { period: 'custom', from: '2026-10-02', to: '2026-10-31' }
    end
    expect(response.parsed_body).to include('available' => true, 'initial' => 1, 'retained' => 1, 'value' => 100.0)
    expect([JrcRelationship::Assignment.count, JrcRelationship::RetentionState.count, JrcCrm::AuditEvent.count]).to eq(counts)
  end

  it 'distinguishes a real zero retention result from a zero denominator' do
    configure
    observation(assignment, at: 1)
    observation(assignment, at: 10, status: 'churned')
    JrcRelationship::RetentionCoverage.create!(account: account, started_at: Time.utc(2026, 9, 30))
    travel_to(Time.utc(2026, 11, 2)) do
      get base, headers: headers, params: { period: 'custom', from: '2026-10-02', to: '2026-10-31' }
    end
    expect(response.parsed_body).to include('available' => true, 'initial' => 1, 'retained' => 0, 'value' => 0.0)
  end

  it 'shows no percentage for an empty initial cohort' do
    configure
    JrcRelationship::RetentionCoverage.create!(account: account, started_at: Time.utc(2026, 9, 30))
    historical_query
    expect(response.parsed_body).to include('available' => false, 'value' => nil)
  end

  it 'does not include an account or portfolio outside the current authorization' do
    configure
    foreign = create(:account)
    other = create(:user, account: foreign, role: :administrator)
    group = JrcRelationship::PortfolioGroup.create!(account: foreign, owner: other, name: 'Synthetic foreign cohort')
    travel_to(Time.utc(2026, 11, 2)) do
      get base, headers: headers, params: { period: 'monthly', reference: '2026-10-01', portfolio_group_id: group.id }
    end
    expect(response).to have_http_status(:not_found)
  end

  it 'refuses modifying or removing historical observations through direct SQL' do
    row = observation(assignment, at: 1)
    expect do
      JrcRelationship::RetentionState.transaction(requires_new: true) { JrcRelationship::RetentionState.where(id: row.id).update_all(facts: {}) }
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect do
      JrcRelationship::RetentionState.transaction(requires_new: true) { JrcRelationship::RetentionState.where(id: row.id).delete_all }
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(row.reload.facts['status']).to eq('active')
  end

  it 'captures subsequent real status changes without rewriting the first observation' do
    assignment
    JrcRelationship::RetentionHistory.start!(context, reason: 'Synthetic native capture')
    original = JrcRelationship::RetentionState.where(account: account).order(:id).first.attributes
    assignment.update!(status: 'churned')
    expect(JrcRelationship::RetentionState.where(account: account).order(:id).last.facts['status']).to eq('churned')
    expect(JrcRelationship::RetentionState.find(original['id']).attributes).to eq(original)
  end
  it 'returns the previous period explicitly without confusing membership with context' do
    configure
    observation(assignment, at: 1)
    JrcRelationship::RetentionCoverage.create!(account: account, started_at: Time.utc(2026, 9, 30))
    travel_to(Time.utc(2026, 11, 2)) do
      get base, headers: headers, params: { period: 'custom', from: '2026-10-02', to: '2026-10-02' }
    end
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body).to include('available' => true, 'value' => 100.0)
    expect(response.parsed_body.fetch('previous')).to include('from' => '2026-10-01', 'available' => false)
  end

  it 'returns an unavailable previous period instead of an error when coverage is missing' do
    configure
    historical_query
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('previous')).to include('available' => false, 'code' => 'insufficient_history')
  end

end
