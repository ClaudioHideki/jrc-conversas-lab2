require 'rails_helper'

RSpec.describe 'Relationship success-plan commitment ownership', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:target) { create(:user, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:headers) { actor.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/records/plans" }
  let(:goal) { { metric: 'usage', baseline: 1, current: 2, target: 10, owner_id: target.id } }
  let(:milestone) { { title: 'Synthetic adoption review', owner_id: target.id, due_at: 2.days.from_now.iso8601 } }
  let(:fields) do
    { assignment_id: assignment.id, request_id: SecureRandom.uuid, title: 'Synthetic success plan', goals: [goal], milestones: [milestone] }
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'refuses new metric responsibilities assigned to an inactive user' do
    target.update!(confirmed_at: nil)
    post url, headers: headers, params: { record: fields.merge(milestones: []) }, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(JrcRelationship::SuccessPlan.where(account: account)).not_to exist
  end

  it 'refuses new milestone responsibilities assigned to an inactive user' do
    target.update!(confirmed_at: nil)
    post url, headers: headers, params: { record: fields.merge(goals: []) }, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(JrcRelationship::SuccessPlan.where(account: account)).not_to exist
  end

  it 'refuses an account member outside the native portfolio scope' do
    target.account_users.find_by!(account: account).update!(role: :agent)
    post url, headers: headers, params: { record: fields }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(JrcRelationship::SuccessPlan.where(account: account)).not_to exist
  end

  it 'persists offline owners and preserves unchanged inactive historical responsibilities on later edits' do
    target.account_users.find_by!(account: account).update!(availability: :offline)
    post url, headers: headers, params: { record: fields }, as: :json
    expect(response).to have_http_status(:created)
    plan = JrcRelationship::SuccessPlan.find(response.parsed_body.fetch('id'))
    target.update!(confirmed_at: nil)
    patch "#{url}/#{plan.id}", headers: headers, params: { record: fields.merge(title: 'Synthetic revised plan', lock_version: plan.lock_version) },
                               as: :json
    expect(response).to have_http_status(:ok)
    expect(plan.reload.owner_id).to eq(actor.id)
    expect(plan.goals.first.fetch('owner_id')).to eq(target.id)
    expect(plan.metadata.fetch('milestones').first.fetch('owner_id')).to eq(target.id)
  end

  it 'rolls back a plan whose new target cannot read its native linked CRM activity' do
    native_context = JrcRelationship::Context.new(member)
    activity = JrcRelationship::Workflow.new(native_context).activity!(assignment: assignment, title: 'Synthetic native source',
                                                                       due_at: 2.days.from_now, request_id: SecureRandom.uuid)
    role = create(:custom_role, account: account,
                                permissions: %w[contact_manage jrc_relationship_view jrc_relationship_manage jrc_relationship_team])
    target.account_users.find_by!(account: account).update!(role: :agent, custom_role: role)
    team = create(:team, account: account)
    team.team_members.create!(user: target)
    assignment.update!(team: team)
    before = JrcCrm::AuditEvent.where(account: account).count
    post url, headers: headers, params: { record: fields.merge(goals: [goal.merge(activity_id: activity.id)]) }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(JrcRelationship::SuccessPlan.where(account: account)).not_to exist
    expect(JrcCrm::AuditEvent.where(account: account).count).to eq(before)
    expect(activity.reload.user_id).to eq(actor.id)
  end
end
