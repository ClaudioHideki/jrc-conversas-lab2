require 'rails_helper'

RSpec.describe JrcRelationship::AutomaticActionCooldown do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:context) { JrcRelationship::Context.new(account.account_users.find_by!(user: user)) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: user, contact: create(:contact, account: account)) }
  let(:configuration) { JrcRelationship::Configuration.create!(account: account, rules: { automatic_action_cooldown_hours: 72 }) }
  let(:signals) { { health: { score: 30, band: 'critical' }, days_without_contact: 0, _source_ids: {} } }
  let(:processor) { JrcRelationship::Processor.new(context: context, assignment: assignment) }
  let(:perform) do
    lambda do |data = signals|
      assignment.with_lock { processor.action!('health', 'Synthetic health cause', data, configuration.effective_rules) }
    end
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  # Reuses the real operator completion transaction across several gate cases.
  def complete_action(action)
    JrcRelationship::Workflow.new(context).save(kind: 'actions', id: action.id,
                                                attributes: { assignment_id: assignment.id, lock_version: action.lock_version, status: 'completed',
                                                              result: 'Synthetic reviewed completion', customer_confirmation: 'not_applicable' })
  end

  it 'suppresses only the exact completed cause across days, preserves history and audits repeated evaluations once' do
    action = perform.call
    complete_action(action)
    original = action.reload.attributes.deep_dup
    travel_to(1.day.from_now) do
      2.times { expect(perform.call).to be_nil }
    end
    expect(assignment.actions.count).to eq(1)
    audits = JrcCrm::AuditEvent.where(account: account, resource_type: assignment.class.name, resource_id: assignment.id)
                               .where("metadata ->> 'action' = 'automatic_action_suppressed'")
    expect(audits.count).to eq(1)
    expect(audits.first.to_value).to include('closed_action_id' => action.id, 'cooldown_hours' => 72, 'reason' => 'unchanged_closed_cause')
    expect(action.reload.attributes).to eq(original)
  end

  it 'admits the cause at the exact expiry and preserves default zero/legacy daily behavior' do
    action = perform.call
    complete_action(action)
    expiry = action.reload.completed_at + 72.hours
    travel_to(expiry - Rational(1, 1_000_000), with_usec: true) { expect(perform.call).to be_nil }
    travel_to(expiry, with_usec: true) { expect(perform.call).to be_persisted }
    expect(assignment.actions.count).to eq(2)
    configuration.update!(rules: { automatic_action_cooldown_hours: 0 })
    expect(described_class.new(context: context, assignment: assignment, digest: action.metadata.fetch('automatic_cause_digest'),
                               hours: 0).allow?).to be(true)
  end

  it 'does not delay a changed actual measurement' do
    action = perform.call
    complete_action(action)
    travel_to(1.day.from_now) do
      expect(perform.call(signals.deep_merge(health: { score: 10 }))).to be_persisted
    end
    expect(assignment.actions.count).to eq(2)
  end

  it 'does not delay a new authorized source identity even if the health score is unchanged' do
    action = perform.call
    complete_action(action)
    survey = JrcRelationship::Survey.create!(account: account, assignment: assignment, kind: 'nps', token_digest: SecureRandom.hex,
                                             expires_at: 3.days.from_now, status: 'responded', score: 3, responded_at: Time.current)
    travel_to(1.day.from_now) do
      expect(perform.call(signals.merge(_source_ids: { surveys: [survey.id] }))).to be_persisted
    end
    expect(assignment.actions.count).to eq(2)
  end

  it 'updates active evidence and retains the operator manual priority instead of applying a closed-cause cooldown' do
    action = perform.call
    JrcRelationship::Workflow.new(context).save(kind: 'actions', id: action.id,
                                                attributes: { assignment_id: assignment.id, lock_version: action.lock_version, priority: 77 })
    updated = perform.call(signals.deep_merge(health: { score: 10 }))
    expect(updated.id).to eq(action.id)
    expect(updated.priority).to eq(77)
    expect(updated.metadata.fetch('automatic_cause_digest')).not_to eq(action.metadata.fetch('automatic_cause_digest'))
    expect(assignment.actions.count).to eq(1)
  end

  it 'does not reinterpret a legacy closed action lacking the exact cause proof' do
    previous = assignment.actions.create!(account: account, owner: user, kind: 'health', reason: 'Legacy local observation',
                                          source_key: "health:#{Date.current}", status: 'completed', completed_by: user,
                                          completed_at: Time.current, result: 'Handled')
    original = previous.attributes.deep_dup
    travel_to(1.day.from_now) { expect(perform.call).to be_persisted }
    expect(previous.reload.attributes).to eq(original)
  end

  it 'does not share a closed cause between customers and rejects a foreign portfolio before auditing' do
    action = perform.call
    complete_action(action)
    other = JrcRelationship::Assignment.create!(account: account, owner: user, contact: create(:contact, account: account))
    gate = described_class.new(context: context, assignment: other, digest: action.metadata.fetch('automatic_cause_digest'), hours: 72)
    expect(gate.allow?).to be(true)
    foreign = create(:account)
    hidden = JrcRelationship::Assignment.create!(account: foreign, contact: create(:contact, account: foreign))
    gate = described_class.new(context: context, assignment: hidden, digest: action.metadata.fetch('automatic_cause_digest'), hours: 72)
    expect { gate.allow? }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'preserves risk visibility and does not execute a new playbook after suppressing the repeated task in the full processor' do
    weights = JrcRelationship::Configuration::DEFAULT_WEIGHTS.transform_values { 0 }.merge('adoption' => 100)
    configuration.update!(weights: weights, rules: { automatic_action_cooldown_hours: 72, no_contact_days: 1000 })
    JrcRelationship::SuccessPlan.create!(account: account, assignment: assignment, owner: user, title: 'Synthetic measured adoption',
                                         goals: [{ metric: 'adoption', target: 100, current: 0, evidence: 'Synthetic local observation' }])
    JrcRelationship::Playbook.create!(account: account, name: 'Synthetic health follow-up', active: true, trigger_kind: 'health',
                                      steps: [{ kind: 'activity', title: 'Review synthetic health', after_days: 0 }])
    2.times { processor.call }
    action = assignment.actions.find_by!(kind: 'health')
    complete_action(action)
    activities = account.jrc_crm_activities.count
    executions = JrcRelationship::PlaybookExecution.where(account: account).count
    travel_to(1.day.from_now) do
      expect { processor.call }.not_to(change { assignment.actions.count })
    end
    expect(context.records(JrcRelationship::RiskCase).where(assignment: assignment, status: %w[detected analyzing planned negotiating])).to exist
    expect(account.jrc_crm_activities.count).to eq(activities)
    expect(JrcRelationship::PlaybookExecution.where(account: account).count).to eq(executions)
  end

  it 'reauthorizes a cached context before any suppression audit after management permission is revoked' do
    action = perform.call
    complete_action(action)
    role = create(:custom_role, account: account, permissions: %w[contact_manage jrc_crm jrc_relationship_view])
    account.account_users.find_by!(user: user).update!(custom_role: role)
    gate = described_class.new(context: context, assignment: assignment, digest: action.metadata.fetch('automatic_cause_digest'), hours: 72)
    expect { gate.allow? }.to raise_error(Pundit::NotAuthorizedError)
    expect(assignment.actions.count).to eq(1)
  end

  context 'with the native resolved critical-ticket signal job' do
    include_context 'JRC Service Desk domain'
    include JrcServiceDeskLifecycleFixtures
    let(:account) { sd_account }
    let(:user) { sd_user }
    let(:assignment) { JrcRelationship::Assignment.create!(account: account, owner: user, contact: sd_contact) }

    before { sd_as_admin! }

    it 'handles a suppressed follow-up in both processing and the native event path without executing another playbook' do
      configuration
      assignment
      sd_priority.update!(code: 'P1')
      lc_publish
      ticket = sd_ticket
      lc_execute(ticket, 'resolve', note: 'Synthetic local resolution', solution: 'Synthetic reviewed resolution')
      JrcRelationship::Playbook.create!(account: account, name: 'Synthetic critical follow-up', active: true, trigger_kind: 'ticket',
                                        steps: [{ kind: 'activity', title: 'Follow up synthetic critical ticket', after_days: 0 }])
      2.times { JrcRelationship::SignalJob.perform_now(ticket.class.name, ticket.id) }
      action = assignment.actions.find_by!(kind: 'post_ticket')
      complete_action(action)
      executions = JrcRelationship::PlaybookExecution.where(account: account).count
      activities = account.jrc_crm_activities.count
      travel_to(1.day.from_now) do
        expect { JrcRelationship::SignalJob.perform_now(ticket.class.name, ticket.id) }.not_to(change { assignment.actions.count })
      end
      expect(JrcRelationship::PlaybookExecution.where(account: account).count).to eq(executions)
      expect(account.jrc_crm_activities.count).to eq(activities)
    end
  end
end
