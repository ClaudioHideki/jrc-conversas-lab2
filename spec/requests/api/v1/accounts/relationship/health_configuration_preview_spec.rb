require 'rails_helper'

RSpec.describe 'Native read-only draft health configuration preview', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:weights) { JrcRelationship::Configuration::DEFAULT_WEIGHTS.transform_values { 0 }.merge('adoption' => 100) }
  let(:configuration) { JrcRelationship::Configuration.create!(account: account, weights: weights) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/configuration/health_preview" }
  let(:payload) do
    { assignment_id: assignment.id, scope_key: 'account', version: configuration.version,
      weights: weights.merge('adoption' => 0, 'relationship' => 100), rules: configuration.effective_rules }
  end
  let(:plan) do
    JrcRelationship::SuccessPlan.create!(account: account, assignment: assignment, owner: actor, title: 'Synthetic real adoption source',
                                         goals: [{ 'metric' => 'adoption', 'target' => 100, 'current' => 50,
                                                   'evidence' => 'Synthetic measured evidence' }])
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'uses real authorized sources and the native calculator without saving configurations, snapshots, actions, audits or jobs' do
    plan
    configuration
    before = [configuration.attributes, JrcRelationship::ConfigurationVersion.count, JrcRelationship::HealthSnapshot.count,
              JrcRelationship::Action.count, JrcCrm::AuditEvent.count, ActiveJob::Base.queue_adapter.enqueued_jobs.count]
    post url, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:ok), response.body
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.parsed_body).to include('simulation' => true, 'business_writes_performed' => false, 'draft_effective' => true)
    expect(response.parsed_body.dig('current', 'health', 'score')).to eq(50)
    expect(response.parsed_body.dig('proposed', 'health', 'score')).to eq(100)
    expect([configuration.reload.attributes, JrcRelationship::ConfigurationVersion.count, JrcRelationship::HealthSnapshot.count,
            JrcRelationship::Action.count, JrcCrm::AuditEvent.count, ActiveJob::Base.queue_adapter.enqueued_jobs.count]).to eq(before)
  end

  it 'preserves native product precedence rather than pretending an account draft overrides it' do
    product = create(:jrc_crm_product, account: account)
    assignment.update!(settings: { product_id: product.id })
    plan
    JrcRelationship::Configuration.create!(account: account, scope_key: "product:#{product.id}", weights: weights)
    post url, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('draft_effective')).to be(false)
    expect(response.parsed_body.values_at('current', 'proposed').map { |row| row.dig('health', 'score') }).to eq([50, 50])
    expect(response.parsed_body.dig('proposed', 'scope_key')).to eq("product:#{product.id}")
  end

  it 'rejects stale versions and invalid draft weights without mutating the active policy' do
    input = payload
    original = configuration.attributes.deep_dup
    post url, headers: headers, params: input.merge(version: configuration.version + 1), as: :json
    expect(response).to have_http_status(:conflict)
    post url, headers: headers, params: input.merge(weights: { adoption: 3 }), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post url, headers: headers, params: input.merge(weights: 'not-an-object'), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(configuration.reload.attributes).to eq(original)
  end

  it 'denies ordinary analysts and foreign accounts without returning health evidence or a customer label' do
    input = payload
    analyst = create(:user, account: account, role: :agent)
    post url, headers: analyst.create_new_auth_token, params: input, as: :json
    expect(response).to have_http_status(:forbidden)
    foreign = create(:user, account: create(:account), role: :administrator)
    post url, headers: foreign.create_new_auth_token, params: input, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).not_to have_key('customer')
  end

  it 'does not expose a customer in another operating unit even to an administrator with a different native unit grant' do
    company = account.master_companies.create!(name: 'Synthetic preview operator', relationship_type: 'internal', tax_id: '11444777000161')
    units = Array.new(2) do |index|
      account.jrc_crm_business_units.create!(name: "Synthetic preview unit #{index}", code: SecureRandom.hex(6), company_id: company.id)
    end
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: company,
                                                business_unit: units.first, active: true, structure_managed: true)
    assignment.update!(business_unit: units.last)
    post url, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).not_to have_key('customer')
    expect(response.parsed_body).not_to have_key('current')
  end
end
