require 'rails_helper'

RSpec.describe JrcRelationship::AnalystEligibility do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:analyst) { create(:user, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: analyst) }
  let(:context) { JrcRelationship::Context.new(actor.account_users.find_by!(account: account)) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'rechecks withdrawal for an already held Context without revoking other native access' do
    previous = JrcRelationship::Context.new(member)
    expect(previous.policy.access?).to be(true)
    member.update!(jrc_relationship_withdrawn_at: Time.current)
    expect(previous.policy.access?).to be(false)
    expect(JrcCustomers::DirectoryPolicy.new(previous.to_h, :directory).access?).to be(true)
    expect(JrcRelationship::RoutingAvailability.new(context, assignment).call(analyst)).to be(false)
    expect(JrcRelationship::WorkOwnership.new(context, assignment).options.map(&:first)).not_to include(analyst.id)
  end

  it 'blocks direct new assignment and transfer admission even without configured capacity limits' do
    assignment
    member.update!(jrc_relationship_withdrawn_at: Time.current)
    expect { assignment.update!(owner: analyst) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(assignment.reload.owner_id).to eq(actor.id)
    expect do
      JrcRelationship::Assignment.create!(account: account, owner: analyst, contact: create(:contact, account: account))
    end.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'preserves historical ownership and rejects its reactivation after withdrawal' do
    historical = JrcRelationship::Assignment.create!(account: account, owner: analyst, status: 'inactive',
                                                     contact: create(:contact, account: account))
    member.update!(jrc_relationship_withdrawn_at: Time.current)
    historical.update!(settings: { 'complexity' => 'historical' })
    expect(historical.reload.owner_id).to eq(analyst.id)
    expect { historical.update!(status: 'active') }.to raise_error(ActiveRecord::RecordInvalid)
    expect(historical.reload.status).to eq('inactive')
  end

  it 'blocks newly assigned work and nested commitments while retaining unchanged historical nested owners' do
    plan = JrcRelationship::SuccessPlan.create!(account: account, assignment: assignment, owner: actor, title: 'Synthetic historical goal',
                                                goals: [{ 'metric' => 'Delivery', 'owner_id' => analyst.id }])
    member.update!(jrc_relationship_withdrawn_at: Time.current)
    plan.update!(title: 'Synthetic clarified historical goal')
    expect(plan.reload.goals.first['owner_id']).to eq(analyst.id)
    expect do
      JrcRelationship::Action.create!(account: account, assignment: assignment, owner: analyst, kind: 'manual',
                                      reason: 'Synthetic blocked responsibility', source_key: SecureRandom.uuid)
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect do
      plan.update!(metadata: { 'milestones' => [{ 'title' => 'New handover', 'owner_id' => analyst.id.to_s }] })
    end.to raise_error(ActiveRecord::RecordInvalid)
    expect(plan.reload.metadata).not_to have_key('milestones')
    expect do
      JrcRelationship::Qbr.create!(account: account, assignment: assignment, owner: actor, title: 'Synthetic blocked future obligation',
                                   scheduled_at: 1.day.from_now, decisions: [{ 'title' => 'New delivery', 'owner_id' => analyst.id }])
    end.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'does not suspend the same user in another account' do
    other = create(:account)
    other.enable_features!('jrc_customer_master', 'jrc_relationship')
    other_member = create(:account_user, account: other, user: analyst, role: :agent)
    member.update!(jrc_relationship_withdrawn_at: Time.current)
    expect(JrcRelationship::Context.new(other_member).policy.access?).to be(true)
    other_assignment = JrcRelationship::Assignment.create!(account: other, owner: analyst, contact: create(:contact, account: other))
    expect(other_assignment.owner_id).to eq(analyst.id)
  end

  it 'preserves survey authorship independently of CS working eligibility' do
    member.update!(jrc_relationship_withdrawn_at: Time.current)
    survey = JrcRelationship::Survey.create!(account: account, assignment: assignment, owner: analyst, kind: 'nps',
                                             token_digest: SecureRandom.hex(32), expires_at: 1.week.from_now)
    expect(survey.owner_id).to eq(analyst.id)
    expect(member.reload).to be_persisted
  end
end
