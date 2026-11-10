require 'rails_helper'

RSpec.describe 'Relationship processing evidence' do
  let(:account) { create(:account) }
  let(:analyst) { create(:user, account: account, role: :agent) }
  let(:manager) { create(:user, account: account, role: :administrator) }
  let(:membership) { account.account_users.find_by!(user: analyst) }
  let!(:assignment) { JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account), owner: analyst) }
  let(:context) { JrcRelationship::Context.new(membership) }
  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'records an actual completed execution and does not include unauthorized assignment IDs' do
    other = JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account), owner: manager)
    JrcRelationship::RefreshJob.perform_now(membership.id, [assignment.id, other.id])
    run = JrcRelationship::ProcessingRun.last!
    expect(run).to have_attributes(state: 'completed', requested_ids: [assignment.id], outcomes: { assignment.id.to_s => 'processed' })
    expect(run.finished_at).to be_present
    expect(JrcRelationship::ProcessingRun.latest_for(context, context.assignments)).to eq(run)
    assignment.update!(owner: manager)
    expect(JrcRelationship::ProcessingRun.latest_for(JrcRelationship::Context.new(membership), context.assignments)).to be_nil
  end

  it 'records a failure without storing the exception content and still raises for the real job retry' do
    processor = instance_double(JrcRelationship::Processor)
    allow(JrcRelationship::Processor).to receive(:new).and_return(processor)
    allow(processor).to receive(:call).and_raise(StandardError, 'SENSITIVE synthetic failure detail')
    expect { JrcRelationship::RefreshJob.perform_now(membership.id, [assignment.id]) }.to raise_error(StandardError)
    run = JrcRelationship::ProcessingRun.last!
    expect(run).to have_attributes(state: 'failed', outcomes: { assignment.id.to_s => 'processing_failed' })
    expect(run.attributes.to_json).not_to include('SENSITIVE')
  end

  it 'deduplicates related health causes without merging unrelated finance and service cases' do
    processor = JrcRelationship::Processor.new(context: context, assignment: assignment)
    data = { health: { score: 55 }, days_without_contact: 1, _source_ids: {} }
    rules = context.configuration.effective_rules
    first = processor.action!('health_drop', 'Health drop', data, rules)
    second = processor.action!('health', 'Low health', data, rules)
    third = processor.action!('finance', 'Separate overdue balance', data, rules)
    expect(second.id).to eq(first.id)
    expect(third.id).not_to eq(first.id)
    expect(first.reload.metadata['related_signals']).to contain_exactly('health', 'health_drop')
    expect(first.priority).to be >= rules['health_drop_action_priority']
  end

  it 'continues monitoring unassigned customers through an authorized manager without assigning them' do
    manager
    assignment.update!(owner: nil)
    clear_enqueued_jobs
    JrcRelationship::SchedulerJob.perform_now
    member = account.account_users.find_by!(user: manager)
    expect(JrcRelationship::RefreshJob).to have_been_enqueued.with(member.id, [assignment.id])
    expect(assignment.reload.owner_id).to be_nil
  end

  it 'stops processing remaining customers after permission is revoked during a batch' do
    second = JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account), owner: analyst)
    allow_any_instance_of(JrcRelationship::Processor).to receive(:call).and_wrap_original do |original|
      result = original.call
      account.disable_features!('jrc_relationship')
      result
    end
    expect { JrcRelationship::RefreshJob.perform_now(membership.id, [assignment.id, second.id]) }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcRelationship::HealthSnapshot.where(assignment: second)).to be_empty
    expect(JrcRelationship::ProcessingRun.last!.outcomes).to eq(assignment.id.to_s => 'processed', second.id.to_s => 'processing_failed')
  end

  it 'does not create another overdue-activity alert from its own projected follow-up' do
    action = JrcRelationship::Action.create!(account: account, assignment: assignment, owner: analyst, kind: 'manual',
                                            reason: 'Synthetic previous commitment', source_key: 'previous', due_at: 1.day.ago)
    JrcRelationship::Workflow.new(context).project_action!(action)
    signals = JrcRelationship::CustomerSignals.new(context: context, assignment: assignment).call
    expect(signals[:overdue_activities]).to eq(0)
    lead = create(:jrc_crm_lead, account: account, owner: analyst, contact: assignment.contact)
    JrcCrm::Activity.create!(account: account, contact: assignment.contact, lead: lead, user: analyst, title: 'Independent native CRM commitment',
                             activity_type: 'task', due_at: 1.day.ago)
    expect(JrcRelationship::CustomerSignals.new(context: context, assignment: assignment).call[:overdue_activities]).to eq(1)
  end
end
