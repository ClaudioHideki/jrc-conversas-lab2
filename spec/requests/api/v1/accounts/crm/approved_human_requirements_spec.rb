require 'rails_helper'

RSpec.describe 'Approved Backoffice human requirements', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:contact) { create(:contact, account: account) }
  let(:order) { account.jrc_crm_sales_orders.create!(owner: admin, contact: contact, status: 'approved') }
  let(:operation) { account.jrc_crm_backoffice_requests.create!(sales_order: order, contact: contact, owner: admin, requested_by: admin,
    title: 'Synthetic human requirements', stage: 'documentation', metadata: { finance_required: false }) }
  let(:catalog) { "/api/v1/accounts/#{account.id}/crm/backoffice_requirement_rules" }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/backoffice_requests/#{operation.id}/requirements" }
  before { account.enable_features!('jrc_crm') }

  def publish(kind, reviewer: admin)
    key = SecureRandom.uuid
    definition = { label: "Synthetic #{kind}", kind: kind, stage: 'documentation', required: true, blocking: true,
      instructions: 'Review the native source and record the outcome', reviewer_ids: [reviewer.id], reviewer_team_ids: [] }
    post catalog, headers: headers, as: :json,
      params: { intent: key, version: 0, reason: 'Synthetic reviewed configuration', rule: { definition: definition, state: 'active' } }
    expect(response).to have_http_status(:created), response.body
    key
  end

  %w[consultation confirmation human_activity].each do |kind|
    it "records an explicit human outcome for #{kind}, not a generic success checkbox" do
      key = publish(kind)
      plan = JrcBackoffice::Requirements.current(operation)
      value = kind == 'confirmation' ? 'confirmed' : 'completed'
      post "#{url}/answer", headers: headers, as: :json, params: { key: key, plan_revision: plan.version,
        response_revision: 0, answer: { decision: value, note: 'Synthetic source reviewed by the authorized actor' }, reason: 'Human review' }
      expect(response).to have_http_status(:ok), response.body
      expect(response.parsed_body.fetch('items').first['status']).to eq('satisfied')
      expect(plan.responses.last.actor_id).to eq(admin.id)
    end
  end

  it 'rejects a configured human answer from another authorized analyst who is not a reviewer' do
    reviewer = create(:user, account: account, role: :administrator)
    key = publish('consultation', reviewer: reviewer)
    plan = JrcBackoffice::Requirements.current(operation)
    post "#{url}/answer", headers: headers, as: :json, params: { key: key, plan_revision: plan.version,
      response_revision: 0, answer: { decision: 'completed', note: 'Not the configured reviewer' }, reason: 'Denied review' }
    expect(response).to have_http_status(:unauthorized)
    expect(plan.responses).to be_empty
  end

  it 'does not publish a human rule with a foreign-account reviewer' do
    foreign = create(:user, account: create(:account))
    post catalog, headers: headers, as: :json, params: { intent: SecureRandom.uuid, version: 0, reason: 'Synthetic invalid reviewer',
      rule: { definition: { label: 'Foreign reviewer', kind: 'human_activity', stage: 'documentation', required: true,
        blocking: true, instructions: 'Review source', reviewer_ids: [foreign.id], reviewer_team_ids: [] } } }
    expect(response).to have_http_status(:not_found)
    expect(JrcBackoffice::RequirementRule.where(account: account)).not_to exist
  end

  it 'never accepts a manually submitted assertion of signatory powers' do
    key = SecureRandom.uuid
    post catalog, headers: headers, as: :json, params: { intent: key, version: 0, reason: 'Synthetic powers gate',
      rule: { definition: { label: 'Human powers proof', kind: 'validation', source: 'signatory_powers',
        stage: 'contract', required: true, blocking: true } } }
    expect(response).to have_http_status(:created)
    plan = JrcBackoffice::Requirements.current(operation)
    post "#{url}/answer", headers: headers, as: :json, params: { key: key, plan_revision: plan.version,
      response_revision: 0, answer: { decision: 'approved' }, reason: 'Cannot replace native human authority proof' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(plan.responses).to be_empty
  end
end
