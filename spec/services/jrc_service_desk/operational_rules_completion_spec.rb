# frozen_string_literal: true

require 'rails_helper'

# Native SQL/permissions tests. Must run in an isolated migrated PostgreSQL database.
RSpec.describe JrcServiceDesk::PublishOperationalRulesService do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures

  before { sd_as_admin! }

  def publish(kind, definition = nil, enabled: true, expected: 0, unit: sd_unit, **definition_fields)
    definition ||= definition_fields
    described_class.new(user_context: sd_context).call(unit_id: unit.id, kind: kind, definition: definition,
                                                       enabled: enabled, expected_version: expected)
  end

  def row(output = nil, match = {}, key: 'rule', precedence: 1, **output_fields)
    output ||= output_fields
    { 'key' => key, 'precedence' => precedence, 'match' => match, 'output' => output }
  end

  def create_ticket(values = sd_create_attributes, key: SecureRandom.uuid, conversation: nil)
    JrcServiceDesk::CreateTicketService.new(user_context: sd_context).call(unit_id: sd_unit.id, attributes: values,
                                                                           idempotency_key: key, intake_conversation: conversation)
  end

  it 'publishes immutable, scoped versions and refuses a stale update' do
    queue = create(:jrc_sd_queue, unit: sd_unit)
    definition = { 'rules' => [row('queue_id' => queue.id)] }
    version = publish('routing', definition)
    expect(version.reload.digest).to eq(version.expected_digest)
    expect(version.published_by_membership).to eq(sd_membership)
    expect { version.update!(enabled: false) }.to raise_error(ActiveRecord::RecordInvalid)
    version.reload
    version.enabled = false
    version.digest = version.expected_digest
    expect { version.save! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect(version.reload.enabled).to be(true)
    expect { publish('routing', definition) }.to raise_error(JrcServiceDesk::IdempotencyConflict)
    expect(JrcServiceDesk::OperationalRuleVersion.count).to eq(1)
  end

  it 'uses an explicit disabled latest version instead of falling back to an old enabled one' do
    queue = create(:jrc_sd_queue, unit: sd_unit)
    definition = { 'rules' => [row('queue_id' => queue.id)] }
    old = publish('routing', definition)
    queue.update!(active: false)
    latest = publish('routing', definition, enabled: false, expected: 1)
    expect(latest.enabled).to be(false)
    expect(old.reload.enabled).to be(true)
    expect(create_ticket.queue_id).to be_nil
  end

  it 'does not permit a queue from a different unit or Account' do
    [sd_other_unit, sd_foreign_unit].each do |unit|
      queue = create(:jrc_sd_queue, unit: unit)
      expect { publish('routing', 'rules' => [row('queue_id' => queue.id)]) }.to raise_error(ActiveRecord::RecordNotFound)
    end
    expect(JrcServiceDesk::OperationalRuleVersion.count).to eq(0)
  end

  it 'does not let an ordinary agent publish configuration or read the administrative scope' do
    sd_account_user.update!(role: :agent)
    expect do
      publish('recurrence', 'window_days' => 14, 'minimum_occurrences' => 2,
                            'group_by' => ['service_id'])
    end.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcServiceDesk::OperationalRuleVersionPolicy::Scope.new(sd_context, JrcServiceDesk::OperationalRuleVersion).resolve).to be_empty
  end

  it 'rejects a publisher whose unit membership was revoked' do
    sd_membership.update!(active: false)
    expect do
      publish('recurrence', 'window_days' => 14, 'minimum_occurrences' => 2,
                            'group_by' => ['service_id'])
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'resolves impact and urgency at creation and persists the published rule reference' do
    chosen = create(:jrc_sd_priority, unit: sd_unit)
    matrix = { 'rules' => [row({ 'priority_id' => chosen.id }, { 'impact' => 'wide', 'urgency' => 'urgent' })] }
    version = publish('priority_matrix', matrix)
    input = sd_create_attributes.except(:priority_id).merge(impact_code: 'wide', urgency_code: 'urgent')
    ticket = create_ticket(input)
    expect(ticket.reload.priority_id).to eq(chosen.id)
    expect(ticket.impact_code).to eq('wide')
    expect(ticket.catalogue_snapshot.dig('operational_rules', 'priority_matrix', 'version_id')).to eq(version.id)
    expect { ticket.update!(impact_code: 'different') }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'does not silently replace an explicit conflicting priority' do
    chosen = create(:jrc_sd_priority, unit: sd_unit)
    publish('priority_matrix', 'rules' => [row({ 'priority_id' => chosen.id }, { 'impact' => 'wide', 'urgency' => 'urgent' })])
    expect do
      create_ticket(sd_create_attributes.merge(impact_code: 'wide',
                                               urgency_code: 'urgent'))
    end.to raise_error(JrcServiceDesk::IdempotencyConflict)
    expect(JrcServiceDesk::Ticket.where(account: sd_account, unit: sd_unit).count).to eq(0)
  end

  it 'rejects missing and equally ranked matching matrix entries without storing a ticket' do
    predicates = { 'impact' => 'wide', 'urgency' => 'urgent' }
    entries = [row({ 'priority_id' => sd_priority.id }, predicates), row({ 'priority_id' => sd_priority.id }, predicates, key: 'other')]
    publish('priority_matrix', 'rules' => entries)
    expect do
      create_ticket(sd_create_attributes.except(:priority_id).merge(impact_code: 'wide',
                                                                    urgency_code: 'urgent'))
    end.to raise_error(JrcServiceDesk::OperationalRuleMatcher::Ambiguous)
    expect do
      create_ticket(sd_create_attributes.except(:priority_id).merge(impact_code: 'small',
                                                                    urgency_code: 'urgent'))
    end.to raise_error(ArgumentError)
    expect(JrcServiceDesk::Ticket.where(account: sd_account, unit: sd_unit).count).to eq(0)
  end

  it 'binds a native Inbox to a queue and keeps explicit assignment precedence' do
    conversation = create(:conversation, account: sd_account, contact: sd_contact)
    create(:inbox_member, inbox: conversation.inbox, user: sd_user)
    queue = create(:jrc_sd_queue, unit: sd_unit)
    manual = create(:jrc_sd_queue, unit: sd_unit)
    publish('routing', 'rules' => [row({ 'queue_id' => queue.id }, { 'inbox_id' => conversation.inbox_id })])
    routed = create_ticket(conversation: conversation)
    expect(routed.reload.queue_id).to eq(queue.id)
    expect(create_ticket(sd_create_attributes.merge(queue_id: manual.id), conversation: conversation).queue_id).to eq(manual.id)
  end

  it 'does not apply a channel rule without the actual authorized conversation' do
    conversation = create(:conversation, account: sd_account, contact: sd_contact)
    queue = create(:jrc_sd_queue, unit: sd_unit)
    publish('routing', 'rules' => [row({ 'queue_id' => queue.id }, { 'inbox_id' => conversation.inbox_id })])
    expect(create_ticket.queue_id).to be_nil
  end

  it 'preserves creation idempotency after publishing a new routing version' do
    first_queue = create(:jrc_sd_queue, unit: sd_unit)
    second_queue = create(:jrc_sd_queue, unit: sd_unit)
    publish('routing', 'rules' => [row('queue_id' => first_queue.id)])
    first = create_ticket(key: 'same-intake')
    publish('routing', { 'rules' => [row('queue_id' => second_queue.id)] }, expected: 1)
    replay = create_ticket(key: 'same-intake')
    expect(replay.id).to eq(first.id)
    expect(replay.queue_id).to eq(first_queue.id)
    expect(JrcServiceDesk::Ticket.where(account: sd_account, unit: sd_unit).count).to eq(1)
  end

  it 'selects explicit budget/calendar conditions and lets the native lifecycle create its clocks' do
    lc_publish(definition: lc_definition(tracked: true))
    conditions = sd_snapshot_attributes.deep_stringify_keys.except('captured_at')
    conditions['timezone'] = 'UTC'
    conditions['calendar_conditions'] = { 'format' => JrcServiceDesk::SnapshotCalendar::VERSION,
                                          'weekly' => (1..7).to_h { |day| [day.to_s, [['00:00', '24:00']]] }, 'holidays' => [], 'exceptions' => {} }
    conditions['policy_conditions'] = { 'clock_budgets_seconds' => { 'first_response' => 60, 'resolution' => 600 } }
    publish('sla_selection', 'rules' => [row('snapshot' => conditions)])
    ticket = create_ticket
    expect(ticket.sla_snapshots.count).to eq(1)
    expect(ticket.latest_sla_snapshot.policy_conditions).to eq(conditions['policy_conditions'])
    lc_execute(ticket, 'work_status')
    clock = ticket.sla_cycles.last.sla_clocks.find_by!(kind: 'resolution')
    expect(clock.budget_seconds).to eq(600)
    expect(clock.due_at - ticket.opened_at).to be_within(0.001).of(600)
  end

  it 'does not publish an invalid calendar as an enabled configuration' do
    conditions = sd_snapshot_attributes.deep_stringify_keys.except('captured_at')
    conditions['policy_conditions'] = { 'clock_budgets_seconds' => { 'first_response' => 60, 'resolution' => 600 } }
    expect { publish('sla_selection', 'rules' => [row('snapshot' => conditions)]) }.to raise_error(ArgumentError)
    expect(JrcServiceDesk::OperationalRuleVersion.count).to eq(0)
  end
end
