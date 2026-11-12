require 'rails_helper'

RSpec.describe 'Analyst withdrawal nested commitments', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:analyst) { create(:user, account: account, role: :agent) }
  let(:allocation) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/team/#{analyst.id}/withdrawal_readiness" }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'blocks readiness for goal and milestone ownership independently of the plan owner without changing history' do
    plan = JrcRelationship::SuccessPlan.create!(account: account, assignment: allocation, owner: actor, title: 'Synthetic active plan',
                                                goals: [{ 'metric' => 'Adoption', 'owner_id' => analyst.id }],
                                                metadata: { 'milestones' => [{ 'title' => 'Review', 'owner_id' => analyst.id.to_s }] })
    get url, headers: actor.create_new_auth_token
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('counts')).to include('plans' => 0, 'plan_commitments' => 1)
    expect(response.parsed_body.fetch('state')).to eq('pending_responsibilities')
    expect(plan.reload.goals.first['owner_id']).to eq(analyst.id)
  end

  it 'includes scheduled QBR decisions but preserves completed historical plans and QBR decisions' do
    plan = JrcRelationship::SuccessPlan.create!(account: account, assignment: allocation, owner: actor, title: 'Synthetic historic plan',
                                                status: 'completed', goals: [{ 'metric' => 'Delivery', 'owner_id' => analyst.id }])
    qbr = JrcRelationship::Qbr.create!(account: account, assignment: allocation, owner: actor, title: 'Synthetic scheduled QBR',
                                       scheduled_at: 1.day.from_now, decisions: [{ 'title' => 'Future commitment', 'owner_id' => analyst.id }])
    get url, headers: actor.create_new_auth_token
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('counts')).to include('plan_commitments' => 0, 'qbr_commitments' => 1)
    qbr.update!(status: 'completed', summary: 'Synthetic historical summary',
                decisions: [{ 'title' => 'Future commitment', 'owner_id' => analyst.id, 'due_at' => 2.days.from_now.iso8601 }])
    get url, headers: actor.create_new_auth_token
    expect(response.parsed_body.fetch('state')).to eq('ready_for_final_review')
    expect(plan.reload.goals.first['owner_id']).to eq(analyst.id)
  end

  it 'changes the digest when the nested owner changes and counts no other account commitments' do
    other = create(:account)
    foreign_assignment = JrcRelationship::Assignment.create!(account: other, contact: create(:contact, account: other))
    JrcRelationship::SuccessPlan.create!(account: other, assignment: foreign_assignment, title: 'Synthetic foreign plan',
                                         goals: [{ 'metric' => 'Foreign', 'owner_id' => analyst.id }])
    get url, headers: actor.create_new_auth_token
    first = response.parsed_body.fetch('snapshot_digest')
    plan = JrcRelationship::SuccessPlan.create!(account: account, assignment: allocation, owner: actor, title: 'Synthetic changed plan',
                                                goals: [{ 'metric' => 'Delivery', 'owner_id' => analyst.id }])
    get url, headers: actor.create_new_auth_token
    expect(response.parsed_body.fetch('snapshot_digest')).not_to eq(first)
    plan.update!(goals: [{ 'metric' => 'Delivery', 'owner_id' => actor.id }])
    get url, headers: actor.create_new_auth_token
    expect(response.parsed_body.fetch('counts')).to include('plan_commitments' => 0, 'qbr_commitments' => 0)
  end

  it 'denies hidden nested work instead of reporting a ready zero count' do
    role = account.custom_roles.create!(name: 'Synthetic scoped reviewer', permissions: %w[jrc_relationship_view jrc_relationship_team])
    actor.account_users.find_by!(account: account).update!(custom_role: role)
    allocation.update!(owner: nil, team: create(:team, account: account))
    JrcRelationship::SuccessPlan.create!(account: account, assignment: allocation, title: 'Synthetic hidden plan',
                                         goals: [{ 'metric' => 'Hidden goal', 'owner_id' => analyst.id }])
    get url, headers: actor.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).not_to have_key('counts')
    expect(response.parsed_body).not_to have_key('snapshot_digest')
  end
end
