require 'rails_helper'

# Native persistence, callbacks, routing and PostgreSQL queries. Requires test Rails boot and the existing migrations.
RSpec.describe 'Relationship operational regression' do
  include_context 'JRC Service Desk domain'
  let(:company) { sd_account.master_companies.create!(name: 'CS operational customer') }
  let(:assignment) { JrcRelationship::Assignment.create!(account: sd_account, company: company, owner: sd_user) }
  let(:context) { JrcRelationship::Context.new(sd_account_user) }
  let(:workflow) { JrcRelationship::Workflow.new(context) }
  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    sd_contact.update!(master_company: company)
  end

  it 'accepts operations_configured without weakening the audit allowlist' do
    audit = JrcCrm::AuditEvent.new(account: sd_account, resource_type: 'JrcOperations::Queue', resource_id: 1, event_type: 'operations_configured')
    expect(audit).to be_valid
    audit.event_type = 'invented_event'
    expect(audit).not_to be_valid
  end

  it 'keeps the action and its native Agenda projection synchronized across pause/resume' do
    action = workflow.save(kind: 'actions', attributes: { assignment_id: assignment.id, request_id: 'pause', reason: 'Pause test', due_at: 2.hours.from_now })[:record]
    original = action.sla_due_at
    original_due = action.due_at
    started = Time.current
    travel_to(started + 1.hour) do
      workflow.save(kind: 'actions', id: action.id, attributes: { assignment_id: assignment.id, lock_version: action.reload.lock_version, status: 'waiting_customer' })
      expect(action.reload.activity.metadata['relationship_sla_paused_at']).to be_present
      expect(action.activity.overdue?).to be(false)
    end
    travel_to(started + 3.hours) do
      agenda = JrcOperations::Agenda.new(account_user: sd_account_user, filters: { source: 'crm', from: started.to_date.iso8601, to: started.to_date.iso8601 }).call
      expect(agenda[:data].find { |row| row[:activity_id] == action.activity_id }[:overdue]).to be(false)
    end
    travel_to(started + 4.hours) do
      workflow.save(kind: 'actions', id: action.id, attributes: { assignment_id: assignment.id, lock_version: action.reload.lock_version, status: 'in_progress' })
      expect(action.reload.sla_due_at).to be_within(1.second).of(original + 3.hours)
      expect(action.due_at).to be_within(1.second).of(original_due + 3.hours)
      expect(action.activity.reload.due_at).to eq(action.due_at)
      expect(action.activity.metadata).not_to have_key('relationship_sla_paused_at')
    end
  end

  it 'reuses a waiting-customer preventive action on a later day and counts it separately from overdue' do
    assignment.update!(created_at: 40.days.ago)
    JrcRelationship::Processor.new(context: context, assignment: assignment).call
    action = assignment.actions.find_by!(kind: 'no_contact')
    workflow.save(kind: 'actions', id: action.id, attributes: { assignment_id: assignment.id, lock_version: action.lock_version, status: 'waiting_customer' })
    travel_to(2.days.from_now) do
      JrcRelationship::Processor.new(context: context, assignment: assignment).call
      expect(assignment.actions.where(kind: 'no_contact').pluck(:id)).to eq([action.id])
      dashboard = JrcRelationship::Presenter.new(context).dashboard(context.assignments)
      expect(dashboard[:waiting_customer_actions]).to eq(1)
      expect(JrcRelationship::TeamMetrics.new(context: context, scope: context.assignments).call[sd_user.id][:waiting_customer_actions]).to eq(1)
    end
  end

  it 'routes QBR and playbook activities through the same clocks and stops the clock on Agenda completion' do
    qbr = workflow.save(kind: 'qbrs', attributes: { assignment_id: assignment.id, request_id: 'qbr', title: 'Quarterly review', scheduled_at: 1.day.from_now })[:record]
    assignment.with_lock { JrcRelationship::Playbooks.new(context).run!(assignment, 'onboarded') }
    actions = assignment.actions.where.not(activity_id: nil)
    expect(actions.count).to eq(5)
    expect(actions.where(operations_queue_id: nil).count).to eq(0)
    expect(actions.where(operations_sla_policy_id: nil).count).to eq(0)
    qbr.activity.update!(status: 'completed', completed_at: Time.current)
    action = actions.find_by!(activity_id: qbr.activity_id)
    expect(action.status).to eq('completed')
    expect(action.first_action_at).to be_present
    expect(JrcOperations::SlaClock.new(action).snapshot[:state]).to eq('stopped')
  end

  it 'preserves a responsible user explicitly selected by the manager' do
    selected = create(:user, account: sd_account, role: :agent)
    JrcOperations::Queue.create!(account: sd_account, name: 'Rotating CS', code: 'CS-ROTATING', assignment_strategy: 'round_robin', settings: { scopes: ['relationship'] })
    action = workflow.save(kind: 'actions', attributes: { assignment_id: assignment.id, request_id: 'owner', reason: 'Selected owner', owner_id: selected.id })[:record]
    expect(action.owner_id).to eq(selected.id)
    expect(action.activity.user_id).to eq(selected.id)
  end

  it 'creates a new default policy for a new configuration and preserves old action policies' do
    configuration = JrcRelationship::Configuration.create!(account: sd_account, rules: { sla_hours: 24, detractor_sla_hours: 4 })
    first = JrcRelationship::Action.new(account: sd_account, assignment: assignment, kind: 'satisfaction', reason: 'First', source_key: 'first')
    JrcRelationship::OperationalRouting.new(context).prepare!(first)
    first.save!
    old_policy = first.operations_sla_policy
    configuration.update!(version: 2, rules: { sla_hours: 48, detractor_sla_hours: 8 })
    second = JrcRelationship::Action.new(account: sd_account, assignment: assignment, kind: 'satisfaction', reason: 'Second', source_key: 'second')
    JrcRelationship::OperationalRouting.new(JrcRelationship::Context.new(sd_account_user)).prepare!(second)
    expect(second.operations_sla_policy_id).not_to eq(old_policy.id)
    expect(second.operations_sla_policy.first_action_minutes).to eq(480)
    expect(second.operations_sla_policy.total_minutes).to eq(2880)
    expect(old_policy.reload.first_action_minutes).to eq(240)
    expect(first.reload.operations_sla_policy_id).to eq(old_policy.id)
  end

  it 'respects direct unit/team restrictions and keeps CS-only queues out of Backoffice' do
    internal = sd_account.master_companies.create!(name: 'Internal CS operator', relationship_type: 'internal')
    unit = JrcCrm::BusinessUnit.create!(account: sd_account, operating_company: internal, name: 'CS A', code: 'CS-A')
    other_unit = JrcCrm::BusinessUnit.create!(account: sd_account, operating_company: internal, name: 'CS B', code: 'CS-B')
    team = create(:team, account: sd_account)
    assignment.update!(business_unit: unit, team: team)
    wrong = JrcOperations::Queue.create!(account: sd_account, name: 'Other unit', code: 'OTHER', business_unit: other_unit, settings: { scopes: ['relationship'] })
    correct = JrcOperations::Queue.create!(account: sd_account, name: 'Assigned unit/team', code: 'CORRECT', business_unit: unit, team: team, settings: { scopes: ['relationship'] })
    action = workflow.save(kind: 'actions', attributes: { assignment_id: assignment.id, request_id: 'unit', reason: 'Unit routing' })[:record]
    expect(action.operations_queue_id).to eq(correct.id)
    expect(wrong.supports_scope?('backoffice')).to be(false)
    order = JrcCrm::SalesOrder.create!(account: sd_account, contact: sd_contact, owner: sd_user, business_unit: unit, source_type: 'manual', order_origin: 'direct_sale')
    result = JrcOperations::BackofficeRouter.new(account: sd_account, order: order, request_kind: 'fulfillment', priority: 'normal').call
    expect(result.queue.code).to eq('BACKOFFICE-GERAL')
  end

  it 'projects a direct order alert without a fake deal and rejects a different account source' do
    order = JrcCrm::SalesOrder.create!(account: sd_account, contact: sd_contact, owner: sd_user, source_type: 'manual', order_origin: 'direct_sale')
    request = JrcCrm::BackofficeRequest.create!(account: sd_account, sales_order: order, owner: sd_user, requested_by: sd_user, contact: sd_contact, title: 'Direct order')
    2.times { JrcOperations::SlaMonitorJob.new.send(:create_operational_alert!, request, 75, { state: 'attention', total_due_at: 1.hour.from_now }) }
    alerts = sd_account.jrc_crm_activities.where('metadata @> ?', { backoffice_request_id: request.id }.to_json)
    expect(alerts.count).to eq(1)
    expect(alerts.first.deal_id).to be_nil
    expect(alerts.first.contact_id).to eq(sd_contact.id)
    expect(alerts.first.company).to eq(company)
    foreign = alerts.first.dup
    foreign.account = sd_foreign_account
    foreign.user = create(:user, account: sd_foreign_account)
    foreign.contact = create(:contact, account: sd_foreign_account)
    foreign.company = nil
    expect(foreign).not_to be_valid
  end

  it 'notifies a configured pre-breach SLA threshold once and suppresses paused alerts' do
    policy = JrcOperations::SlaPolicy.create!(account: sd_account, name: 'Thresholds', scope_kind: 'relationship',
      total_minutes: 240, first_action_minutes: 240, alert_thresholds: [50, 75, 90, 100], pause_statuses: ['waiting_customer'])
    action = workflow.save(kind: 'actions', attributes: { assignment_id: assignment.id, request_id: 'threshold', reason: 'Contact' })[:record]
    action.update_columns(operations_sla_policy_id: policy.id, sla_started_at: 130.minutes.ago,
      sla_due_at: 110.minutes.from_now, first_action_due_at: 110.minutes.from_now)
    action.reload
    2.times { JrcRelationship::SlaMonitorJob.perform_now(sd_account.id) }
    audits = JrcCrm::AuditEvent.where(account: sd_account, resource_type: action.class.name, resource_id: action.id)
    expect(audits.where(event_type: 'operations_sla_threshold').count).to eq(1)
    expect(audits.where(event_type: 'operations_sla_violated').count).to eq(0)
    action.update!(status: 'waiting_customer')
    action.update_columns(sla_started_at: 200.minutes.ago)
    JrcRelationship::SlaMonitorJob.perform_now(sd_account.id)
    expect(audits.where(event_type: 'operations_sla_threshold').count).to eq(1)
  end
  it 'pauses finance waiting through the existing default SLA and preserves one pause across reasons' do
    assignment.update!(created_at: 40.days.ago)
    processor = JrcRelationship::Processor.new(context: context, assignment: assignment)
    processor.call
    action = assignment.actions.find_by!(kind: 'no_contact')
    started = Time.current
    original = action.sla_due_at
    original_due = action.due_at
    travel_to(started + 1.hour) do
      workflow.save(kind: 'actions', id: action.id, attributes: { assignment_id: assignment.id,
        lock_version: action.reload.lock_version, status: 'waiting_finance' })
      expect(action.reload.activity.metadata['relationship_sla_paused_at']).to be_present
      expect(action.activity.status).to eq('scheduled')
    end
    travel_to(started + 2.days) do
      processor.call
      expect(assignment.actions.where(kind: 'no_contact').pluck(:id)).to eq([action.id])
      expect(JrcRelationship::Presenter.new(context).dashboard(context.assignments)[:waiting_finance_actions]).to eq(1)
      expect(JrcRelationship::TeamMetrics.new(context: context, scope: context.assignments).call[sd_user.id][:waiting_finance_actions]).to eq(1)
      data = JrcRelationship::MetricDrilldown.new(context: context, scope: context.assignments).call(metric: 'waiting_finance_actions')
      expect(data[:total]).to eq(1)
      paused = action.reload.sla_paused_at
      workflow.save(kind: 'actions', id: action.id, attributes: { assignment_id: assignment.id,
        lock_version: action.lock_version, status: 'waiting_customer' })
      expect(action.reload.sla_paused_at).to eq(paused)
      workflow.save(kind: 'actions', id: action.id, attributes: { assignment_id: assignment.id,
        lock_version: action.lock_version, status: 'in_progress' })
      expect(action.reload.sla_due_at).to be_within(1.second).of(original + 47.hours)
      expect(action.due_at).to be_within(1.second).of(original_due + 47.hours)
      expect(action.activity.reload.due_at).to eq(action.due_at)
      expect(action.activity.metadata).not_to have_key('relationship_sla_paused_at')
    end
  end

  it 'extends legacy CS system policies while preserving explicit custom and other-scope pause settings' do
    policy = JrcOperations::SlaPolicy.new(account: sd_account, name: 'Legacy', scope_kind: 'relationship',
      conditions: { system_default: true }, pause_statuses: ['waiting_customer'])
    expect(policy.pause_status?('waiting_finance')).to be(true)
    expect(policy.pause_statuses).to eq(['waiting_customer'])
    policy.conditions = {}
    expect(policy.pause_status?('waiting_finance')).to be(false)
    policy.pause_statuses = %w[waiting_customer waiting_finance]
    expect(policy.pause_status?('waiting_finance')).to be(true)
    policy.scope_kind = 'backoffice'
    policy.pause_statuses = ['waiting_customer']
    policy.conditions = { system_default: true }
    expect(policy.pause_status?('waiting_finance')).to be(false)
  end

  it 'projects a newly created finance-waiting action to the same Agenda with its pause marker' do
    action = workflow.save(kind: 'actions', attributes: { assignment_id: assignment.id, request_id: 'initial-finance-pause',
      reason: 'Finance confirmation', status: 'waiting_finance', due_at: 2.hours.from_now })[:record]
    expect(action.sla_paused_at).to be_present
    expect(action.activity.metadata['relationship_sla_paused_at']).to eq(action.sla_paused_at.iso8601)
    expect(action.activity.status).to eq('scheduled')
  end

end
