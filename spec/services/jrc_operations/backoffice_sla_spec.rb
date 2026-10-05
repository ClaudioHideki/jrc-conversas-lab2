require 'rails_helper'
require Rails.root.join('db/migrate/20261004234100_backfill_jrc_operations_backoffice_routing')

RSpec.describe 'Backoffice routing and SLA' do
  include ActiveSupport::Testing::TimeHelpers

  let(:account) { create(:account) }
  let(:owner) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }
  let(:order) do
    JrcCrm::SalesOrder.create!(account: account, owner: owner, contact: contact,
                             status: 'approved', source_type: 'manual', order_origin: 'direct_sale')
  end
  let(:queue) { JrcOperations::Queue.create!(account: account, name: 'Configured queue', code: 'CONFIGURED') }
  let(:policy) do
    JrcOperations::SlaPolicy.create!(account: account, operations_queue: queue, name: 'Configured SLA',
      first_action_minutes: 30, stage_minutes: 60, total_minutes: 120)
  end
  let(:record) do
    request = JrcCrm::BackofficeRequest.new(account: account, sales_order: order, owner: owner, requested_by: owner,
      title: 'Process order', operations_queue: queue, operations_sla_policy: policy, status: 'in_progress')
    JrcOperations::SlaClock.new(request).start!
    request.save!
    request
  end

  around { |example| Time.use_zone('America/Sao_Paulo') { example.run } }
  after { travel_back }

  it 'freezes thresholds during pause and retains the original budget after resuming' do
    travel_to Time.zone.parse('2026-10-05 10:00')
    record
    travel 30.minutes
    record.update!(status: 'waiting_customer')
    travel 3.hours
    paused = JrcOperations::SlaClock.new(record.reload).snapshot
    expect(paused[:percent_elapsed]).to eq(25.0)
    expect(paused[:triggered_thresholds]).to be_empty
    expect(paused[:first_action_overdue]).to be(false)
    record.update!(status: 'in_progress')
    expect(record.reload.sla_due_at).to eq(Time.zone.parse('2026-10-05 15:00'))
    expect(JrcOperations::SlaClock.new(record).snapshot[:percent_elapsed]).to eq(25.0)
    expect(JrcCrm::AuditEvent.for_resource('JrcCrm::BackofficeRequest', record.id).pluck(:event_type)).to include(
      'operations_assigned', 'operations_sla_paused', 'operations_sla_resumed')
  end

  it 'does not consume weekends and preserves business minutes across a paused weekend' do
    policy.update!(business_hours: { enabled: true, weekdays: [1, 2, 3, 4, 5], start: '08:00', end: '18:00' })
    travel_to Time.zone.parse('2026-10-02 17:30')
    record
    travel_to Time.zone.parse('2026-10-04 12:00')
    expect(JrcOperations::SlaClock.new(record).snapshot[:percent_elapsed]).to eq(25.0)
    travel_to Time.zone.parse('2026-10-05 08:30')
    record.update!(status: 'waiting_customer')
    travel_to Time.zone.parse('2026-10-06 08:30')
    record.update!(status: 'in_progress')
    expect(record.reload.sla_due_at).to eq(Time.zone.parse('2026-10-06 09:30'))
    expect(JrcOperations::SlaClock.new(record).snapshot[:percent_elapsed]).to eq(50.0)
  end

  it 'rejects calendars that would loop forever' do
    policy.business_hours = { enabled: true, weekdays: [8], start: '18:00', end: '08:00' }
    expect(policy).not_to be_valid
    expect(policy.errors[:business_hours]).to be_present
  end

  it 'audits first action and stage deadlines even without a total SLA' do
    travel_to Time.zone.parse('2026-10-05 10:00')
    policy.update!(total_minutes: nil)
    record
    travel 61.minutes
    snapshot = JrcOperations::SlaClock.new(record).snapshot
    expect(snapshot[:state]).to eq('overdue')
    expect(snapshot[:total_overdue]).to be(false)
    JrcOperations::SlaMonitorJob.new.perform(account.id)
    events = JrcCrm::AuditEvent.for_resource('JrcCrm::BackofficeRequest', record.id).where(event_type: 'operations_sla_violated')
    expect(events.pluck(:metadata).map { |row| row['clock_kind'] }).to match_array(%w[first_action stage])
  end

  it 'honors configured queues and policies created after the fallback' do
    routing = JrcOperations::BackofficeRouter.new(account: account, order: order, request_kind: 'fulfillment', priority: 'normal').call
    expect(routing.policy.total_minutes).to be_nil
    queue
    policy
    configured = JrcOperations::BackofficeRouter.new(account: account, order: order, request_kind: 'fulfillment', priority: 'normal').call
    expect(configured.queue).to eq(queue)
    expect(configured.policy).to eq(policy)
  end

  it 'uses manual, round robin, least load and specialty routing within the account' do
    queue.update!(settings: { 'user_ids' => [owner.id, agent.id] })
    record
    queue.update!(assignment_strategy: 'round_robin')
    router = JrcOperations::BackofficeRouter.new(account: account, order: order, request_kind: 'change', priority: 'normal', preferred_owner: owner)
    expect(router.call.owner).to eq(agent)
    queue.update!(assignment_strategy: 'least_load')
    expect(router.call.owner).to eq(agent)
    queue.update!(assignment_strategy: 'specialty', settings: { 'user_ids' => [owner.id, agent.id], 'specialty_user_ids' => [agent.id] })
    expect(router.call.owner).to eq(agent)
    queue.update!(assignment_strategy: 'manual')
    expect(router.call.owner).to eq(owner)
    other = create(:account)
    queue.operating_company = JrcCustomers::Company.create!(account: other, name: 'Other tenant', person_kind: 'organization', relationship_type: 'internal')
    expect(queue).not_to be_valid
  end

  it 'monitors configured thresholds once and audits escalation without duplicating events' do
    travel_to Time.zone.parse('2026-10-05 10:00')
    policy.update!(escalation: { user_id: agent.id })
    record
    travel 121.minutes
    described_job = JrcOperations::SlaMonitorJob.new
    described_job.perform(account.id)
    described_job.perform(account.id)
    expect(record.reload.owner_id).to eq(agent.id)
    events = JrcCrm::AuditEvent.for_resource('JrcCrm::BackofficeRequest', record.id)
    expect(events.where(event_type: 'operations_sla_threshold').count).to eq(4)
    expect(events.where(event_type: 'operations_sla_escalated').count).to eq(1)
    expect(events.where(event_type: 'operations_sla_violated').pluck(:metadata).map { |row| row['clock_kind'] }).to match_array(%w[first_action stage total])
  end

  it 'backfills existing requests idempotently without deadlines or loss of commercial references' do
    record.update_columns(operations_queue_id: nil, operations_sla_policy_id: nil, sla_due_at: nil, due_at: nil)
    migration = BackfillJrcOperationsBackofficeRouting.new
    migration.migrate(:up)
    mapped = record.reload.attributes.slice('sales_order_id', 'owner_id', 'contract_id', 'operations_queue_id', 'operations_sla_policy_id')
    expect(mapped['operations_queue_id']).to be_present
    expect(mapped['operations_sla_policy_id']).to be_present
    migration.migrate(:up)
    expect(record.reload.attributes.slice(*mapped.keys)).to eq(mapped)
    expect(record.sla_due_at).to be_nil
    expect(record.due_at).to be_nil
    expect(JrcOperations::Queue.where(account: account, code: 'BACKOFFICE-GERAL').count).to eq(1)
    connection = ActiveRecord::Base.connection
    expect(connection.foreign_key_exists?(:jrc_crm_backoffice_requests, :jrc_operations_queues, column: :operations_queue_id)).to be(true)
    expect(connection.index_exists?(:jrc_operations_queues, %i[account_id code], unique: true)).to be(true)
  end
end
