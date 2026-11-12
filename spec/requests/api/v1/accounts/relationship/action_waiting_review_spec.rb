require 'rails_helper'

RSpec.describe 'Native relationship waiting reassessment', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:context) { JrcRelationship::Context.new(member) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:policy) do
    JrcOperations::SlaPolicy.create!(account: account, name: 'Native waiting policy', scope_kind: 'relationship', total_minutes: 240,
                                     pause_statuses: %w[waiting_customer waiting_finance])
  end
  let(:action) do
    JrcRelationship::Action.create!(account: account, assignment: assignment, owner: actor, kind: 'manual', reason: 'Source follow-up',
                                    source_key: 'synthetic-pause-review', operations_sla_policy: policy, due_at: 4.hours.from_now)
  end
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/records/actions/#{action.id}" }
  let(:fields) do
    { assignment_id: assignment.id, lock_version: action.lock_version, status: 'waiting_customer',
      waiting_reason: 'Awaiting evidence from the customer', next_step: 'Review received evidence', return_at: 2.hours.from_now.iso8601 }
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'rejects an unbounded wait without persisting a status, SLA pause or partial audit' do
    original = action.reload.attributes.deep_dup
    patch url, headers: headers, as: :json, params: { record: fields.except(:waiting_reason, :next_step, :return_at) }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(action.reload.attributes).to eq(original)
    expect(JrcCrm::AuditEvent.where(account: account, resource_type: action.class.name, resource_id: action.id)).to be_empty
  end

  it 'persists the explicit reason, next step and review date through native status/SLA and audited history' do
    JrcRelationship::Workflow.new(context).project_action!(action)
    patch url, headers: headers, as: :json, params: { record: fields.merge(account_id: -1) }
    expect(response).to have_http_status(:ok), response.body
    expect(action.reload).to have_attributes(status: 'waiting_customer', waiting_reason: fields[:waiting_reason], next_step: fields[:next_step])
    expect([action.sla_paused_at.present?, action.activity.reload.metadata['relationship_sla_paused_at'].present?]).to eq([true, true])
    expect(JrcCrm::AuditEvent.where(account: account, resource_type: action.class.name, resource_id: action.id)
                            .where("to_value -> 'metadata' ->> 'waiting_reason' = ?", fields[:waiting_reason])).to exist
    get url, headers: headers, as: :json
    expect(response.parsed_body.dig('metadata', 'waiting_reason')).to eq(fields[:waiting_reason])
  end

  it 'rejects expired or incomplete new reassessments and protects an existing reason from erasure' do
    [fields.merge(return_at: 1.hour.ago.iso8601), fields.merge(waiting_reason: ' '), fields.merge(waiting_reason: 17),
     fields.merge(next_step: '')].each do |invalid|
      patch url, headers: headers, as: :json, params: { record: invalid }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(action.reload.status).to eq('open')
    end
    action.update!(fields.except(:assignment_id, :lock_version))
    patch url, headers: headers, as: :json, params: { record: fields.merge(lock_version: action.reload.lock_version, waiting_reason: '') }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(action.reload.waiting_reason).to eq(fields[:waiting_reason])
  end

  it 'keeps legacy waiting rows editable for unrelated updates without fabricating a historical reason or review' do
    # Only this synthetic setup represents a persisted row from before the review rule existed.
    action.update_columns(status: 'waiting_customer') # rubocop:disable Rails/SkipsModelValidations
    action.reload
    patch url, headers: headers, as: :json, params: { record: { assignment_id: assignment.id, lock_version: action.lock_version, priority: 72 } }
    expect(response).to have_http_status(:ok), response.body
    expect(action.reload).to have_attributes(status: 'waiting_customer', priority: 72, waiting_reason: nil, return_at: nil)
  end

  it 'requires the same bounded review in a batch and rolls back the batch on incomplete input' do
    endpoint = "/api/v1/accounts/#{account.id}/relationship/actions/batch"
    post endpoint, headers: headers, as: :json, params: { ids: [action.id], record: { status: 'waiting_finance' } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(action.reload.status).to eq('open')
    post endpoint, headers: headers, as: :json, params: { ids: [action.id], record: fields.except(:assignment_id, :lock_version)
                                                                                          .merge(status: 'waiting_finance') }
    expect(response).to have_http_status(:ok), response.body
    expect(action.reload).to have_attributes(status: 'waiting_finance', waiting_reason: fields[:waiting_reason])
  end
end
