require 'rails_helper'

RSpec.describe 'Relationship management requests are intents, not executions', type: :request do
  let(:account) { create(:account) }
  let(:analyst) { create(:user, account: account, role: :agent) }
  let(:manager) { create(:user, account: account, role: :administrator) }
  let(:headers) { analyst.create_new_auth_token }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account), owner: analyst) }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship/management_requests" }
  let(:input) { { kind: 'transfer', assignment_id: assignment.id, reason: 'Synthetic requested transfer', idempotency_key: SecureRandom.uuid } }
  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'allows an analyst to request own-client transfer without moving the customer' do
    original = assignment.attributes
    post base, headers: headers, as: :json, params: { management_request: input }
    expect(response).to have_http_status(:created), response.body
    expect(response.parsed_body).to include('kind' => 'transfer', 'state' => 'pending')
    expect(assignment.reload.attributes).to eq(original)
    expect(JrcRelationship::BatchReview.where(account: account)).not_to exist
  end

  it 'replays an identical intent without duplicate request or audit' do
    values = input
    post base, headers: headers, as: :json, params: { management_request: values }
    id = response.parsed_body['id']
    counts = [JrcRelationship::ManagementRequest.count, JrcCrm::AuditEvent.count]
    post base, headers: headers, as: :json, params: { management_request: values }
    expect(response.parsed_body['id']).to eq(id)
    expect([JrcRelationship::ManagementRequest.count, JrcCrm::AuditEvent.count]).to eq(counts)
  end

  it 'rejects a changed request using the old intent key' do
    values = input
    post base, headers: headers, as: :json, params: { management_request: values }
    post base, headers: headers, as: :json, params: { management_request: values.merge(reason: 'Different intent') }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcRelationship::ManagementRequest.where(account: account).count).to eq(1)
  end

  it 'refuses transfer of another analysts customer' do
    assignment.update!(owner: manager)
    post base, headers: headers, as: :json, params: { management_request: input }
    expect(response).to have_http_status(:not_found)
    expect(JrcRelationship::ManagementRequest.where(account: account)).not_to exist
  end

  it 'requires a nonempty reason' do
    post base, headers: headers, as: :json, params: { management_request: input.merge(reason: ' ') }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcRelationship::ManagementRequest.where(account: account)).not_to exist
  end

  it 'does not let the analyst submit an eligibility-management request or suspend anyone' do
    membership = account.account_users.find_by!(user: manager)
    original = membership.attributes
    post base, headers: headers, as: :json,
      params: { management_request: { kind: 'suspend', analyst_id: manager.id, reason: 'Synthetic denied request', idempotency_key: SecureRandom.uuid } }
    expect(response).to have_http_status(:forbidden)
    expect(membership.reload.attributes).to eq(original)
  end

  it 'preserves the requester receipt but removes the customer reference after loss of scope' do
    post base, headers: headers, as: :json, params: { management_request: input }
    assignment.update!(owner: manager)
    get base, headers: headers
    expect(response).to have_http_status(:ok)
    row = response.parsed_body.fetch('payload').first
    expect(row['redacted']).to be(true)
    expect(row).not_to have_key('assignment_id')
    expect(row).not_to have_key('reason')
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'does not accept a different account source' do
    foreign = create(:account)
    row = JrcRelationship::Assignment.create!(account: foreign, contact: create(:contact, account: foreign))
    post base, headers: headers, as: :json, params: { management_request: input.merge(assignment_id: row.id) }
    expect(response).to have_http_status(:not_found)
    expect(JrcRelationship::ManagementRequest.where(account: account)).not_to exist
  end
end
