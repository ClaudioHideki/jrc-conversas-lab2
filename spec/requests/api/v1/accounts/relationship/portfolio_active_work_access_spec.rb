require 'rails_helper'

RSpec.describe 'Native active work access during legacy portfolio handoff', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:target) { create(:user, account: account, role: :agent) }
  let(:target_member) { account.account_users.find_by!(user: target) }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: actor)) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:action) do
    assignment.actions.create!(account: account, owner: actor, kind: 'manual', reason: 'Synthetic active commitment',
                               source_key: SecureRandom.uuid, due_at: 2.days.from_now)
  end
  let(:view_only_role) { account.custom_roles.create!(name: 'Synthetic CS reader', permissions: %w[contact_manage jrc_relationship_view]) }
  let(:headers) { actor.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship/portfolio" }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'refuses to give active work and its Agenda to an access-only recipient and rolls back the whole operation' do
    target_member.update!(custom_role: view_only_role)
    activity = JrcRelationship::Workflow.new(context).project_action!(action)
    expect do
      patch "#{base}/#{assignment.id}", headers: headers, as: :json, params: { assignment: { owner_id: target.id } }
    end.not_to change(JrcCrm::AuditEvent, :count)
    expect(response).to have_http_status(:forbidden)
    expect([assignment.reload.owner_id, action.reload.owner_id, activity.reload.user_id]).to eq([actor.id, actor.id, actor.id])
  end

  it 'refuses blind propagation of a currently hidden action instead of bypassing the native source scope' do
    action.update!(factors: { 'sla' => { 'breached_count' => 0 } })
    expect(context.records(JrcRelationship::Action).exists?(id: action.id)).to be(false)
    patch "#{base}/#{assignment.id}", headers: headers, as: :json, params: { assignment: { owner_id: target.id } }
    expect(response).to have_http_status(:forbidden)
    expect([assignment.reload.owner_id, action.reload.owner_id]).to eq([actor.id, actor.id])
  end

  it 'preserves a complete valid native handoff and closed historical ownership' do
    activity = JrcRelationship::Workflow.new(context).project_action!(action)
    historical = assignment.actions.create!(account: account, owner: actor, kind: 'manual', reason: 'Synthetic closed evidence',
                                            source_key: SecureRandom.uuid, status: 'dismissed', factors: { 'sla' => { 'breached_count' => 0 } })
    original = historical.attributes
    patch "#{base}/#{assignment.id}", headers: headers, as: :json, params: { assignment: { owner_id: target.id } }
    expect(response).to have_http_status(:ok)
    expect([assignment.reload.owner_id, action.reload.owner_id, activity.reload.user_id]).to eq([target.id, target.id, target.id])
    expect(JrcRelationship::Context.new(target_member).records(JrcRelationship::Action).exists?(id: action.id)).to be(true)
    expect(historical.reload.attributes).to eq(original)
  end

  it 'applies the same pending-work destination checks to the legacy batch endpoint' do
    target_member.update!(custom_role: view_only_role)
    action
    post "#{base}/batch", headers: headers, as: :json, params: {
      ids: [assignment.id], operation: 'assign', owner_id: target.id, request_id: SecureRandom.uuid
    }
    expect(response).to have_http_status(:forbidden)
    expect([assignment.reload.owner_id, action.reload.owner_id]).to eq([actor.id, actor.id])
  end

  it 'retains unrelated and no-op owner edits without moving hidden individually delegated work' do
    action.update!(owner: target, factors: { 'sla' => { 'breached_count' => 0 } })
    patch "#{base}/#{assignment.id}", headers: headers, as: :json, params: {
      assignment: { owner_id: actor.id.to_s, status: 'at_risk' }
    }
    expect(response).to have_http_status(:ok)
    expect(assignment.reload.status).to eq('at_risk')
    expect(action.reload.owner_id).to eq(target.id)
  end

  it 'rolls back every mutation when a recipient cannot access captured conversation evidence and succeeds after a real native grant' do
    conversation = create(:conversation, account: account, contact: assignment.contact, assignee: actor)
    action.update!(metadata: { '_source_ids' => { 'conversations' => [conversation.id] } })
    activity = JrcRelationship::Workflow.new(context).project_action!(action)
    destination = JrcRelationship::Context.new(target_member)
    visibility = JrcCustomers::Visibility.new(account: account, user: target, account_user: target_member)
    expect(visibility.conversations.exists?(id: conversation.id)).to be(false)
    patch "#{base}/#{assignment.id}", headers: headers, as: :json, params: { assignment: { owner_id: target.id } }
    expect(response).to have_http_status(:forbidden)
    expect([assignment.reload.owner_id, action.reload.owner_id, activity.reload.user_id]).to eq([actor.id, actor.id, actor.id])
    expect(destination.assignments.exists?(id: assignment.id)).to be(false)
    create(:inbox_member, inbox: conversation.inbox, user: target)
    patch "#{base}/#{assignment.id}", headers: headers, as: :json, params: { assignment: { owner_id: target.id } }
    expect(response).to have_http_status(:ok)
    expect([assignment.reload.owner_id, action.reload.owner_id, activity.reload.user_id]).to eq([target.id, target.id, target.id])
  end
end
