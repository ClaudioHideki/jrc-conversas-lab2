require 'rails_helper'

RSpec.describe 'Existing operations configuration endpoints', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:crm_url) { "/api/v1/accounts/#{account.id}/crm" }
  let(:relationship_url) { "/api/v1/accounts/#{account.id}/relationship" }
  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'creates and updates a queue with an accepted independent audit each time' do
    post "#{crm_url}/operations_queues", headers: headers, params: { operations_queue: { name: 'CS', code: 'CS', settings: { scopes: ['relationship'] } } }, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch('id')
    patch "#{crm_url}/operations_queues/#{id}", headers: headers, params: { operations_queue: { name: 'CS updated' } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(JrcOperations::Queue.find(id).name).to eq('CS updated')
    expect(JrcCrm::AuditEvent.where(account: account, resource_type: 'JrcOperations::Queue', resource_id: id, event_type: 'operations_configured').count).to eq(2)
  end

  it 'creates and updates a SLA policy without rolling back on its audit' do
    post "#{crm_url}/operations_sla_policies", headers: headers, params: { operations_sla_policy: { name: 'CS SLA', scope_kind: 'relationship', first_action_minutes: 240, total_minutes: 1440 } }, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch('id')
    patch "#{crm_url}/operations_sla_policies/#{id}", headers: headers, params: { operations_sla_policy: { total_minutes: 2880 } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(JrcOperations::SlaPolicy.find(id).total_minutes).to eq(2880)
    expect(JrcCrm::AuditEvent.where(account: account, resource_type: 'JrcOperations::SlaPolicy', resource_id: id, event_type: 'operations_configured').count).to eq(2)
  end

  it 'rejects updates to another account queue' do
    foreign = JrcOperations::Queue.create!(account: create(:account), name: 'Foreign', code: 'FOREIGN')
    patch "#{crm_url}/operations_queues/#{foreign.id}", headers: headers, params: { operations_queue: { name: 'Changed' } }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(foreign.reload.name).to eq('Foreign')
  end

  it 'returns real immutable Health Score configuration revisions with actor and scoped rules' do
    get "#{relationship_url}/configuration", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    original = response.parsed_body
    patch "#{relationship_url}/configuration", headers: headers,
      params: original.slice('scope_key', 'version', 'weights', 'rules').merge('rules' => original['rules'].merge('sla_hours' => 48)), as: :json
    expect(response).to have_http_status(:ok)
    revisions = response.parsed_body.fetch('history')
    expect(revisions.pluck('version')).to eq([2, 1])
    expect(revisions.first).to include('actor_id' => admin.id)
    expect(revisions.first.fetch('rules')['sla_hours']).to eq(48)
    expect(revisions.last.fetch('rules')['sla_hours']).to eq(24)
    version = JrcRelationship::ConfigurationVersion.where(account: account, version: 2).first!
    expect { version.update!(weights: {}) }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'versions risk reasons and rejects invalid catalogs without losing the previous configuration' do
    get "#{relationship_url}/configuration", headers: headers, as: :json
    original = response.parsed_body.slice('scope_key', 'version', 'weights', 'rules')
    patch "#{relationship_url}/configuration", headers: headers, params: original.merge('rules' => original['rules'].merge('risk_reasons' => ['Produto', 'Prazo'])), as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('rules')['risk_reasons']).to eq(['Produto', 'Prazo'])
    current = response.parsed_body.slice('scope_key', 'version', 'weights', 'rules')
    patch "#{relationship_url}/configuration", headers: headers, params: current.merge('rules' => current['rules'].merge('risk_reasons' => [nil])), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcRelationship::Configuration.find_by!(account: account).effective_rules['risk_reasons']).to eq(['Produto', 'Prazo'])
  end
end
