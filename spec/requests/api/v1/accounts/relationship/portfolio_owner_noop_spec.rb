require 'rails_helper'

RSpec.describe 'Relationship unchanged portfolio owner', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:delegate) { create(:user, account: account, role: :administrator) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: actor)) }
  let(:action) do
    JrcRelationship::Workflow.new(context).save(kind: 'actions', attributes: {
                                                  assignment_id: assignment.id, request_id: SecureRandom.uuid, owner_id: delegate.id,
                                                  reason: 'Synthetic specifically delegated work', due_at: 2.days.from_now
                                                }).fetch(:record)
  end
  let(:headers) { actor.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship" }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  def facts
    { action: action.reload.attributes.slice('owner_id', 'lock_version', 'due_at'),
      activity: action.activity.reload.attributes.slice('user_id', 'due_at', 'updated_at') }
  end

  it 'retains specifically delegated action and Agenda ownership when the owner is posted unchanged' do
    before = facts
    patch "#{base}/portfolio/#{assignment.id}", headers: headers, as: :json, params: { assignment: { owner_id: actor.id } }
    expect(response).to have_http_status(:ok)
    expect(assignment.reload.owner_id).to eq(actor.id)
    expect(facts).to eq(before)
  end

  it 'still persists unrelated portfolio changes when an HTML-style unchanged owner ID is supplied' do
    before = facts
    patch "#{base}/portfolio/#{assignment.id}", headers: headers, as: :json,
                                                params: { assignment: { owner_id: actor.id.to_s, status: 'at_risk' } }
    expect(response).to have_http_status(:ok)
    expect(assignment.reload.status).to eq('at_risk')
    expect(facts).to eq(before)
  end

  it 'does not clear a delegated action when an already unassigned portfolio is posted unassigned' do
    before = facts
    assignment.update!(owner: nil)
    patch "#{base}/portfolio/#{assignment.id}", headers: headers, as: :json, params: { assignment: { owner_id: nil } }
    expect(response).to have_http_status(:ok)
    expect(assignment.reload.owner_id).to be_nil
    expect(facts).to eq(before)
  end

  it 'keeps the native reviewed item receipt while avoiding implicit redistribution on an unchanged owner' do
    before = facts
    post "#{base}/reviewed_batches", headers: headers, as: :json, params: {
      ids: [assignment.id], operation: 'assign', owner_id: actor.id, request_id: SecureRandom.uuid
    }
    expect(response).to have_http_status(:ok)
    plan = response.parsed_body
    post "#{base}/reviewed_batches/#{plan.fetch('id')}/approve", headers: headers, as: :json, params: { digest: plan.fetch('digest') }
    expect(response).to have_http_status(:ok)
    JrcRelationship::BatchExecutionJob.perform_now(plan.fetch('id'))
    review = JrcRelationship::BatchReview.find(plan.fetch('id'))
    expect(review.state).to eq('completed')
    expect(review.items.first.receipt.fetch('resources').first).to include('owner_id' => actor.id)
    expect(facts).to eq(before)
  end

  it 'preserves the established propagation when the portfolio owner actually changes' do
    action
    target = create(:user, account: account, role: :administrator)
    patch "#{base}/portfolio/#{assignment.id}", headers: headers, as: :json, params: { assignment: { owner_id: target.id } }
    expect(response).to have_http_status(:ok)
    expect(assignment.reload.owner_id).to eq(target.id)
    expect(action.reload.owner_id).to eq(target.id)
    expect(action.activity.reload.user_id).to eq(target.id)
  end
end
