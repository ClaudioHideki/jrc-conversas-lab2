require 'rails_helper'

RSpec.describe 'Native customer recommendation HTTP safety', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:headers) { actor.create_new_auth_token }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/portfolio/#{assignment.id}/recommendations" }

  before do
    account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    weights = JrcRelationship::Configuration::DEFAULT_WEIGHTS.transform_values { 0 }.merge('adoption' => 100)
    JrcRelationship::Configuration.create!(account: account, scope_key: 'account', weights: weights)
  end

  it 'returns real missing-data evidence without caching or business writes' do
    assignment
    models = [JrcRelationship::HealthSnapshot, JrcRelationship::Action, JrcRelationship::RiskCase,
              JrcRelationship::ConfigurationVersion, JrcCrm::AuditEvent]
    original = models.map(&:count) + [ActiveJob::Base.queue_adapter.enqueued_jobs.count]
    get url, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('recommendation_state' => 'unavailable', 'external_actions_require_confirmation' => true,
                                            'customer' => assignment.label)
    expect(response.parsed_body.dig('health', 'score')).to be_nil
    expect(response.parsed_body.keys).not_to include('_source_ids', 'token', 'access_signature')
    expect(models.map(&:count) + [ActiveJob::Base.queue_adapter.enqueued_jobs.count]).to eq(original)
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'does not trust account or user query IDs to authorize a foreign allocation' do
    foreign = create(:account)
    other = JrcRelationship::Assignment.create!(account: foreign, contact: create(:contact, account: foreign))
    get "/api/v1/accounts/#{account.id}/relationship/portfolio/#{other.id}/recommendations", headers: headers,
                                                                                             params: { account_id: foreign.id, user_id: actor.id }
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body.keys).not_to include('customer', 'health', 'evidence')
  end

  it 'rejects a foreign viewer even when a valid local actor ID is supplied' do
    foreign = create(:user, account: create(:account), role: :administrator)
    get url, headers: foreign.create_new_auth_token, params: { user_id: actor.id }
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body.keys).not_to include('customer', 'health', 'evidence')
  end

  it 'rechecks native permissions after the viewer loses the module grant' do
    member.update!(custom_role: create(:custom_role, account: account, permissions: []))
    get url, headers: headers
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body.keys).not_to include('customer', 'health', 'evidence')
  end

  it 'does not trust a unit parameter to expand the current native unit coverage' do
    operator = account.master_companies.create!(name: 'Synthetic recommendation operator', relationship_type: 'internal', tax_id: '11444777000161')
    units = Array.new(2) do |index|
      account.jrc_crm_business_units.create!(name: "Synthetic recommendation unit #{index}", code: SecureRandom.hex(6), company_id: operator.id)
    end
    assignment.update!(business_unit: units.last)
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: operator,
                                                business_unit: units.first, active: true, structure_managed: true)
    get url, headers: headers, params: { unit_id: units.last.id, business_unit_id: units.last.id }
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body.keys).not_to include('customer', 'health', 'evidence')
  end
end
