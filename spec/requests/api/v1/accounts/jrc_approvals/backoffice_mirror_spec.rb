require 'rails_helper'

RSpec.describe 'Backoffice native approval mirror sources', :approval_core, :commercial_approvals, type: :request do
  let(:scope) { approval_scope }
  let(:author) { approval_actor(scope, permissions: JrcApprovals::Authorization::PERMISSIONS + ['jrc_crm'], role: :administrator) }
  let(:reviewer) { approval_actor(scope, permissions: %w[jrc_approvals_decide jrc_crm]) }
  let(:order) do
    JrcCrm::SalesOrder.create!(account: scope[:account], owner: author.user, contact: create(:contact, account: scope[:account]),
                               business_unit: scope[:unit])
  end
  let(:operation) do
    order.backoffice_requests.create!(account: scope[:account], owner: author.user, requested_by: author.user,
                                      business_unit: scope[:unit], title: 'Synthetic mirror request')
  end
  let(:version) { commercial_policy(scope, author, [reviewer], key: 'backoffice.release') }
  let(:record) do
    version
    JrcApprovals::Requests.new(account: scope[:account], user: author.user)
                          .create!(key: 'backoffice.release', resource_id: operation.id, idempotency_key: 'mirror-native').first
  end
  let(:base) { "/api/v1/accounts/#{scope[:account].id}/approvals/requests" }
  let(:headers) { author.user.create_new_auth_token }

  it 'returns native origin-filtered history and detailed decisions without changing immutable captured evidence' do
    approval_vote(scope, reviewer, record)
    before = record.reload.attributes.deep_dup
    get base, headers: headers, params: { resource_type: operation.class.name, resource_id: operation.id, page: 1, per_page: 10 }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.pluck('id')).to eq([record.id])
    get base, headers: headers, params: { resource_type: order.class.name, resource_id: order.id }
    expect(response.parsed_body).to eq([])
    get "#{base}/#{record.id}", headers: headers
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body).to include('resource_type' => operation.class.name, 'resource_id' => operation.id,
                                            'policy_version' => record.policy_version.version, 'state' => 'approved')
    expect(response.parsed_body['decisions']).to include(a_hash_including('actor_name' => reviewer.user.name, 'decision' => 'approved'))
    expect(record.reload.attributes).to eq(before)
  end

  it 'uses native result counts and pagination rather than truncating the origin history locally' do
    record
    second = JrcApprovals::Requests.new(account: scope[:account], user: author.user)
                                   .create!(key: 'backoffice.release', resource_id: operation.id, idempotency_key: 'mirror-second').first
    get base, headers: headers, params: { resource_type: operation.class.name, resource_id: operation.id, page: 2, per_page: 1 }
    expect(response).to have_http_status(:ok), response.body
    expect(response.headers['x-total-count']).to eq('2')
    expect(response.parsed_body.pluck('id')).to eq([second.id])
  end

  it 'does not disclose the origin history after native issuer and unit access is revoked' do
    record
    scope[:account].jrc_crm_user_business_units.find_by!(user_id: author.user.id).update!(active: false)
    get base, headers: headers, params: { resource_type: operation.class.name, resource_id: operation.id }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body).to eq([])
    get "#{base}/#{record.id}", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'denies a foreign account even with the exact native resource and request IDs' do
    record
    foreign = create(:user, account: create(:account), role: :administrator)
    get "#{base}/#{record.id}", headers: foreign.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end
end
