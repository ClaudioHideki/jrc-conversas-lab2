require 'rails_helper'

RSpec.describe JrcRelationship::SlaMonitorJob, type: :job do
  let(:account) { create(:account) }
  let(:owner) { create(:user, account: account, role: :administrator, confirmed_at: Time.current) }
  let(:target) { create(:user, account: account, role: :administrator, confirmed_at: Time.current) }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: owner)) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: owner, contact: create(:contact, account: account)) }
  let(:policy) do
    JrcOperations::SlaPolicy.create!(account: account, name: 'Synthetic escalation policy', scope_kind: 'relationship',
                                     first_action_minutes: 30, total_minutes: 60, escalation: { user_id: target.id })
  end
  let(:action) do
    row = JrcRelationship::Action.create!(account: account, assignment: assignment, owner: owner, operations_sla_policy: policy,
                                          kind: 'manual', reason: 'Synthetic monitored commitment', source_key: SecureRandom.uuid,
                                          priority: 50, sla_started_at: 2.hours.ago, first_action_due_at: 90.minutes.ago,
                                          sla_due_at: 1.hour.ago, due_at: 1.hour.ago)
    JrcRelationship::Workflow.new(context).project_action!(row)
    row
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'keeps actual breach evidence visible without assigning the action or its native Agenda projection to an unauthenticated escalation target' do
    original = action.attributes.slice('owner_id', 'priority', 'activity_id')
    User.find(target.id).update!(confirmed_at: nil)
    described_class.perform_now(account.id)
    expect(action.reload.attributes.slice(*original.keys)).to eq(original)
    expect(action.activity.reload.user_id).to eq(owner.id)
    audits = JrcCrm::AuditEvent.where(account: account, resource_type: action.class.name, resource_id: action.id)
    expect(audits.where(event_type: 'operations_sla_violated')).to exist
    expect(audits.where("metadata ->> 'action' = ?", 'sla_escalated')).not_to exist
  end

  it 'retains native escalation and Agenda ownership for the configured currently authenticated authorized target' do
    action
    described_class.perform_now(account.id)
    expect(action.reload).to have_attributes(owner_id: target.id, priority: 100)
    expect(action.activity.reload.user_id).to eq(target.id)
    audits = JrcCrm::AuditEvent.where(account: account, resource_type: action.class.name, resource_id: action.id)
    expect(audits.where("metadata ->> 'action' = ?", 'sla_escalated')).to exist
  end
end
