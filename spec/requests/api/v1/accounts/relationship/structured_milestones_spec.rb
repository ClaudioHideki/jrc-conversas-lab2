require 'rails_helper'

RSpec.describe 'Relationship bounded milestone input', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:headers) { actor.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/records/plans" }
  let(:fields) { { assignment_id: assignment.id, title: 'Synthetic bounded plan', request_id: SecureRandom.uuid, goals: [] } }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'rejects a hash instead of a milestone array without raising an internal error' do
    post url, headers: headers, as: :json,
              params: { record: fields.merge(milestones: { title: 'Synthetic malformed milestone', owner_id: actor.id }) }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcRelationship::SuccessPlan.where(account: account)).not_to exist
  end

  it 'rejects non-object milestone entries instead of silently discarding their data' do
    post url, headers: headers, as: :json, params: { record: fields.merge(milestones: ['invalid']) }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcRelationship::SuccessPlan.where(account: account)).not_to exist
  end

  it 'rejects more than 50 native milestones before resolving any work owner' do
    checks = []
    allow(JrcRelationship::WorkOwnership).to receive(:new).and_wrap_original do |constructor, *args|
      ownership = constructor.call(*args)
      allow(ownership).to receive(:authorize!).and_wrap_original do |method, *owner_args|
        checks << owner_args.first
        method.call(*owner_args)
      end
      ownership
    end
    rows = Array.new(51) { |index| { title: "Synthetic milestone #{index}", owner_id: actor.id } }
    post url, headers: headers, as: :json, params: { record: fields.merge(milestones: rows) }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(checks).to eq([])
    expect(JrcRelationship::SuccessPlan.where(account: account)).not_to exist
    post url, headers: headers, as: :json, params: { record: fields.merge(milestones: [rows.first]) }
    expect(response).to have_http_status(:created)
    expect(checks).to include(actor.id)
  end

  it 'preserves the existing milestone field allowlist and explicit empty-array clearing' do
    row = { title: 'Synthetic controlled milestone', owner_id: actor.id, notes: 'Evidence', account_id: -1,
            product_id: -1, user_id: -1, status: 'active' }
    post url, headers: headers, as: :json, params: { record: fields.merge(milestones: [row], notes: 'Synthetic plan note') }
    expect(response).to have_http_status(:created)
    plan = JrcRelationship::SuccessPlan.find(response.parsed_body.fetch('id'))
    expect(plan.metadata.fetch('milestones').first).to eq('title' => row[:title], 'owner_id' => actor.id, 'notes' => 'Evidence', 'status' => 'active')
    patch "#{url}/#{plan.id}", headers: headers, as: :json, params: { record: {
      assignment_id: assignment.id, lock_version: plan.lock_version, milestones: []
    } }
    expect(response).to have_http_status(:ok)
    expect(plan.reload.metadata).to include('milestones' => [], 'notes' => 'Synthetic plan note')
  end
end
