require 'rails_helper'

RSpec.describe JrcRelationship::SignalJob, type: :job do
  let(:account) { create(:account) }
  let(:owner) { create(:user, account: account, role: :agent, confirmed_at: Time.current) }
  let(:member) { account.account_users.find_by!(user: owner) }
  let(:contact) { create(:contact, account: account) }
  let(:lead) { create(:jrc_crm_lead, account: account, owner: owner, contact: contact) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: owner, contact: contact) }
  let(:activity) do
    JrcCrm::Activity.create!(account: account, user: owner, contact: contact, lead: lead, title: 'Synthetic event source', activity_type: 'task')
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'does not evaluate a native source using an owner who has lost authentication eligibility' do
    assignment
    activity
    User.find(owner.id).update!(confirmed_at: nil)
    before = [JrcRelationship::HealthSnapshot.where(account: account).count, JrcRelationship::Action.where(account: account).count]
    described_class.perform_now(activity.class.name, activity.id)
    expect([JrcRelationship::HealthSnapshot.where(account: account).count, JrcRelationship::Action.where(account: account).count]).to eq(before)
    expect(assignment.reload.owner_id).to eq(owner.id)
    expect(member.reload).to be_persisted
  end

  it 'continues native monitoring for an authenticated owner whose presence is offline' do
    assignment
    member.update!(availability: :offline)
    described_class.perform_now(activity.class.name, activity.id)
    expect(JrcRelationship::HealthSnapshot.where(account: account, assignment: assignment, viewer: owner)).to exist
    expect(assignment.reload.owner_id).to eq(owner.id)
  end

  it 'preserves the native active-manager monitoring fallback without assigning or removing the inactive owner' do
    manager = create(:user, account: account, role: :administrator, confirmed_at: Time.current)
    manager_member = account.account_users.find_by!(user: manager)
    assignment
    activity
    User.find(owner.id).update!(confirmed_at: nil)
    clear_enqueued_jobs
    # Limit the scheduler's account enumeration to this fixture; all member/portfolio queries and the refresh job are native.
    allow(Account).to receive(:find_each).and_yield(account)
    JrcRelationship::SchedulerJob.perform_now
    expect(JrcRelationship::RefreshJob).to have_been_enqueued.with(manager_member.id, [assignment.id])
    expect(JrcRelationship::RefreshJob).not_to have_been_enqueued.with(member.id, [assignment.id])
    JrcRelationship::RefreshJob.perform_now(manager_member.id, [assignment.id])
    expect(JrcRelationship::HealthSnapshot.where(account: account, assignment: assignment, viewer: manager)).to exist
    expect(assignment.reload.owner_id).to eq(owner.id)
  end
end
