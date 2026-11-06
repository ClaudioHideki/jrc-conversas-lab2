require 'rails_helper'

RSpec.describe 'Own source-free reviewed-operation inventory', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:headers) { actor.create_new_auth_token }
  let(:context) { JrcRelationship::Context.new(member) }
  let(:service) { JrcRelationship::ReviewedPortfolioBatch.new(context) }
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/reviewed_batches" }
  let(:group) { JrcRelationship::PortfolioGroup.create!(account: account, owner: actor, name: 'Synthetic private portfolio name') }
  let(:allocations) do
    Array.new(2) do |index|
      JrcRelationship::Assignment.create!(account: account, owner: actor,
                                          contact: create(:contact, account: account, name: "Synthetic private customer #{index}"))
    end
  end
  let(:input) do
    { 'operation' => 'portfolio_membership', 'ids' => allocations.map(&:id), 'portfolio_group_id' => group.id,
      'expected_version' => group.lock_version, 'active' => true, 'justification' => 'Synthetic private human reason',
      'request_id' => SecureRandom.uuid }
  end
  let(:review) { service.preview(input) }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'pages only the current actor metadata and counters without serializing customer context or frozen snapshots' do
    ids = Array.new(3) { service.preview(input.merge('request_id' => SecureRandom.uuid)).fetch('id') }
    get url, headers: headers, params: { page: 2, per_page: 1, status: 'pending', portfolio_group_id: group.id }
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.parsed_body.fetch('meta')).to eq('page' => 2, 'per_page' => 1, 'total' => 3)
    row = response.parsed_body.fetch('payload').sole
    expect(row).to include('id' => ids.reverse[1], 'state' => 'previewed', 'operation' => 'portfolio_membership', 'can_cancel_pending' => true)
    expect(row.fetch('counts')).to eq('total' => 2, 'pending' => 2, 'applied' => 0, 'failed' => 0, 'canceled' => 0)
    expect(response.body).not_to include(group.name, allocations.first.contact.name, input.fetch('justification'), 'snapshot', 'digest')
  end

  it 'cannot enumerate or cancel another actor intentions even with the account administrator role' do
    saved = review
    other = create(:user, account: account, role: :administrator)
    other_headers = other.create_new_auth_token
    get url, headers: other_headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload')).to eq([])
    post "#{url}/#{saved.fetch('id')}/cancel_pending", headers: other_headers, as: :json,
                                                       params: { expected_revision: 1, reason: 'Not my own operation' }
    expect(response).to have_http_status(:not_found)
    expect(JrcRelationship::BatchReview.find(saved.fetch('id')).state).to eq('previewed')
  end

  it 'stops only own pending intentions after losing source-management access without gaining customer or group details' do
    saved = review
    record = JrcRelationship::BatchReview.find(saved.fetch('id'))
    pinned = record.attributes.slice('inputs', 'snapshot', 'digest')
    role = account.custom_roles.create!(name: 'Synthetic own operations only',
                                        permissions: %w[contact_manage jrc_relationship_view jrc_relationship_manage])
    member.update!(role: :agent, custom_role: role)
    get "#{url}/#{record.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    get url, headers: headers
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([record.id])
    post "#{url}/#{record.id}/cancel_pending", headers: headers, as: :json,
                                               params: { expected_revision: 1, reason: 'Stop my own pending intention; do not change customers' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('id' => record.id, 'state' => 'canceled', 'revision' => 2)
    expect(record.reload.attributes.slice('inputs', 'snapshot', 'digest')).to eq(pinned)
    expect(group.customer_links).not_to exist
    expect(response.body).not_to include(group.name, allocations.first.contact.name, 'snapshot', 'inputs')
  end

  it 'preserves committed receipts and links when stopping the remaining finite work' do
    saved = review
    service.approve(saved.fetch('id'), digest: saved.fetch('digest'))
    service.advance(saved.fetch('id'), limit: 1)
    record = JrcRelationship::BatchReview.find(saved.fetch('id'))
    first = record.items.order(:ordinal).first.attributes
    post "#{url}/#{record.id}/cancel_pending", headers: headers, as: :json,
                                               params: { expected_revision: record.revision, reason: 'Stop only the remaining customer links' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('counts')).to include('applied' => 1, 'canceled' => 1, 'pending' => 0)
    expect(record.items.order(:ordinal).first.reload.attributes).to eq(first)
    expect(group.customer_links.where(active: true).pluck(:assignment_id)).to eq([allocations.first.id])
    expect(allocations.map { |row| row.reload.owner_id }).to eq([actor.id] * 2)
  end

  it 'rejects stale stop confirmation and makes a completed cancellation retry a no-op' do
    saved = review
    service.approve(saved.fetch('id'), digest: saved.fetch('digest'))
    record = JrcRelationship::BatchReview.find(saved.fetch('id'))
    post "#{url}/#{record.id}/cancel_pending", headers: headers, as: :json,
                                               params: { expected_revision: 1, reason: 'Stale inventory confirmation' }
    expect(response).to have_http_status(:conflict)
    expect(record.items.where(state: 'pending').count).to eq(2)
    fields = { expected_revision: record.revision, reason: 'Current inventory confirmation' }
    post "#{url}/#{record.id}/cancel_pending", headers: headers, as: :json, params: fields
    expect(response).to have_http_status(:ok)
    before = [record.reload.attributes, JrcCrm::AuditEvent.count]
    post "#{url}/#{record.id}/cancel_pending", headers: headers, as: :json, params: fields
    expect([record.reload.attributes, JrcCrm::AuditEvent.count]).to eq(before)
  end

  it 'rejects identity overrides, foreign account access and invalid operation filters while retaining native manage denial' do
    review
    get url, headers: headers, params: { user_id: create(:user).id }
    expect(response).to have_http_status(:unprocessable_entity)
    get url, headers: headers, params: { status: 'invented' }
    expect(response).to have_http_status(:unprocessable_entity)
    foreign = create(:account)
    get "/api/v1/accounts/#{foreign.id}/relationship/reviewed_batches", headers: headers
    expect(response).to have_http_status(:forbidden)
    role = account.custom_roles.create!(name: 'Synthetic view only', permissions: %w[contact_manage jrc_relationship_view])
    member.update!(role: :agent, custom_role: role)
    get url, headers: headers
    expect(response).to have_http_status(:forbidden)
  end

  it 'preserves legacy full-detail cancellation and its source-access rollback instead of silently widening that endpoint' do
    saved = review
    post "#{url}/#{saved.fetch('id')}/cancel", headers: headers, as: :json, params: {}
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').pluck('state')).to eq(%w[canceled canceled])
    pending = service.preview(input.merge('request_id' => SecureRandom.uuid))
    role = account.custom_roles.create!(name: 'Synthetic changed source access',
                                        permissions: %w[contact_manage jrc_relationship_view jrc_relationship_manage])
    member.update!(role: :agent, custom_role: role)
    post "#{url}/#{pending.fetch('id')}/cancel", headers: headers, as: :json, params: {}
    expect(response).to have_http_status(:not_found)
    expect(JrcRelationship::BatchReview.find(pending.fetch('id')).state).to eq('previewed')
    expect(group.customer_links).not_to exist
  end
end
