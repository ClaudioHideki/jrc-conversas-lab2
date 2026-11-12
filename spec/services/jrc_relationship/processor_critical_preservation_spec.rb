require 'rails_helper'

RSpec.describe JrcRelationship::Processor do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: actor)) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: create(:contact, account: account)) }
  let(:processor) { described_class.new(context: context, assignment: assignment) }
  let(:data) { { _source_ids: {} } }
  let(:risk) do
    JrcRelationship::RiskCase.create!(account: account, assignment: assignment, owner: actor, kind: 'satisfaction', severity: 'critical',
                                      reason: 'Synthetic retained critical evidence', source_key: SecureRandom.uuid)
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'does not automatically downgrade or duplicate an existing critical case when the daily action budget is exhausted' do
    JrcRelationship::Configuration.create!(account: account, rules: { automatic_action_daily_limit: 1 })
    assignment.actions.create!(account: account, reason: 'Synthetic budget use', kind: 'health', source_key: SecureRandom.uuid,
                               metadata: { automatic: true })
    before = risk.attributes.deep_dup
    2.times { processor.send(:risk!, 'satisfaction', 'Weaker automatic signal', 'high', data) }
    expect(risk.reload.attributes).to eq(before)
    expect(JrcRelationship::RiskCase.where(account: account, assignment: assignment).count).to eq(1)
    expect(JrcCrm::AuditEvent.where(account: account).where("metadata ->> 'action' = 'risk_reclassified'")).to be_empty
  end

  it 'still escalates a less severe open risk from current automatic evidence' do
    risk.update!(severity: 'medium')
    processor.send(:risk!, 'satisfaction', 'Severe current automatic signal', 'critical', data)
    expect(risk.reload.severity).to eq('critical')
    expect(JrcCrm::AuditEvent.where(account: account, resource_id: risk.id).where("metadata ->> 'action' = 'risk_reclassified'").count).to eq(1)
  end

  it 'keeps an authorized explicit human reclassification in the native workflow with its audit trail' do
    risk
    JrcRelationship::Workflow.new(context).save(kind: 'risks', id: risk.id,
                                                attributes: { assignment_id: assignment.id, lock_version: risk.lock_version, severity: 'high' })
    expect(risk.reload.severity).to eq('high')
    expect(JrcCrm::AuditEvent.where(account: account, resource_id: risk.id).where("metadata ->> 'action' = 'updated'")).to exist
  end
end
