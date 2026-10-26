# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Native coordinated routing actions' do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  include ActiveSupport::Testing::TimeHelpers
  let(:queue) { create(:jrc_sd_queue, unit: sd_unit, distribution_mode: 'round_robin') }
  let(:output) { { 'queue_id' => queue.id, 'assignment' => { 'mode' => 'fixed', 'account_user_id' => sd_account_user.id } } }
  let(:definition) { { 'rules' => [{ 'key' => 'synthetic-route', 'precedence' => 4, 'match' => { 'priority_id' => sd_priority.id }, 'output' => output }] } }
  let(:publisher) { JrcServiceDesk::PublishOperationalRulesService.new(user_context: sd_context) }
  let(:workflow) { JrcServiceDesk::CreateTicketWorkflowService.new(user_context: sd_context) }
  before do
    sd_as_admin!
    sd_account_user.update!(availability: :online)
    allow(OnlineStatusTracker).to receive(:effective_presence).with(sd_account.id).and_return(user_ids: [sd_user.id], reason: nil)
    sd_membership.update!(availability: 'available', capacity: 1)
  end

  it 'assigns a fixed eligible collaborator when the queue permits automatic distribution' do
    publisher.call(unit_id: sd_unit.id, kind: 'routing', definition: definition, enabled: true, expected_version: 0)
    ticket = workflow.call(unit_id: sd_unit.id, attributes: sd_create_attributes, idempotency_key: 'fixed-eligible')
    expect(ticket.reload.assignee_membership).to eq(sd_membership)
    expect(ticket.ticket_events.where(event_type: 'ticket_auto_routed').count).to eq(1)
  end

  it 'never uses a fixed published rule to bypass a manual queue' do
    queue.update!(distribution_mode: 'manual')
    publisher.call(unit_id: sd_unit.id, kind: 'routing', definition: definition, enabled: true, expected_version: 0)
    ticket = workflow.call(unit_id: sd_unit.id, attributes: sd_create_attributes, idempotency_key: 'manual-stays-manual')
    expect(ticket.reload.assignee_membership_id).to be_nil
    expect(ticket.ticket_events.where(event_type: 'ticket_auto_routed')).to be_empty
    result = JrcServiceDesk::AutomaticRoutingService.new(user_context: sd_context)
      .preview(unit_id: sd_unit.id, queue_id: queue.id, options: output['assignment'])
    expect(result[:proposed_account_user_id]).to be_nil
    JrcServiceDesk::AssignTicketService.new(user_context: sd_context).call(ticket_id: ticket.id,
      attributes: { assignee_account_user_id: sd_account_user.id }, expected_lock_version: ticket.lock_version)
    expect(ticket.reload.assignee_membership_id).to eq(sd_membership.id)
  end

  it 'keeps an unavailable or saturated fixed target unassigned and records the reason once' do
    sd_membership.update!(availability: 'unavailable')
    publisher.call(unit_id: sd_unit.id, kind: 'routing', definition: definition, enabled: true, expected_version: 0)
    ticket = workflow.call(unit_id: sd_unit.id, attributes: sd_create_attributes, idempotency_key: 'fixed-unavailable')
    2.times { JrcServiceDesk::AutomaticRoutingService.new(user_context: sd_context).call(ticket_id: ticket.id) }
    expect(ticket.reload.assignee_membership_id).to be_nil
    expect(ticket.ticket_events.where("data ->> 'routing_no_candidate' = 'true'").count).to eq(1)
    sd_membership.update!(availability: 'available')
    sd_ticket(assignee_membership: sd_membership)
    JrcServiceDesk::AutomaticRoutingService.new(user_context: sd_context).call(ticket_id: ticket.id)
    expect(ticket.reload.assignee_membership_id).to be_nil
  end

  it 'uses one authorized fallback and preserves the original SLA binding and elapsed clocks' do
    travel_to Time.iso8601('2026-10-26T13:00:00Z')
    fallback = create(:jrc_sd_queue, unit: sd_unit, distribution_mode: 'least_load', required_skills: ['unavailable-skill'])
    output['assignment']['fallback_queue_id'] = fallback.id
    sd_membership.update!(availability: 'unavailable')
    version = lc_publish(definition: lc_definition(tracked: true)).current_version
    publisher.call(unit_id: sd_unit.id, kind: 'routing', definition: definition, enabled: true, expected_version: 0)
    ticket = JrcServiceDesk::CreateTicketService.new(user_context: sd_context).call(unit_id: sd_unit.id, attributes: sd_create_attributes, idempotency_key: 'one-fallback')
    lc_snapshot(ticket)
    JrcServiceDesk::LifecycleClocks.new(ticket: ticket, version: version, actor: sd_membership, now: Time.current).start!
    clocks_before = ticket.sla_cycles.first.sla_clocks.order(:id).map(&:attributes)
    travel 15.minutes
    JrcServiceDesk::AutomaticRoutingService.new(user_context: sd_context).call(ticket_id: ticket.id)
    expect(ticket.reload.queue).to eq(fallback)
    expect(ticket.lifecycle_policy_version_id).to eq(version.id)
    expect(ticket.sla_cycles.count).to eq(1)
    expect(ticket.sla_cycles.first.sla_clocks.order(:id).map(&:attributes)).to eq(clocks_before)
    expect(ticket.ticket_events.where(event_type: 'ticket_transferred').count).to eq(1)
    2.times { JrcServiceDesk::AutomaticRoutingService.new(user_context: sd_context).call(ticket_id: ticket.id) }
    expect(ticket.ticket_events.where(event_type: 'ticket_transferred').count).to eq(1)
    expect(ticket.reload.assignee_membership_id).to be_nil
  end

  it 'simulates eligibility using the native allocator without persisting assignments or execution audit' do
    input = { unit_id: sd_unit.id, queue_id: queue.id, options: output['assignment'] }
    before_counts = [JrcServiceDesk::Ticket, JrcServiceDesk::TicketEvent, JrcServiceDesk::UnitMembership, Audited::Audit].map(&:count)
    result = JrcServiceDesk::AutomaticRoutingService.new(user_context: sd_context).preview(**input)
    expect(result).to include(eligible_members: 1, proposed_account_user_id: sd_account_user.id, creates_assignment: false)
    expect([JrcServiceDesk::Ticket, JrcServiceDesk::TicketEvent, JrcServiceDesk::UnitMembership, Audited::Audit].map(&:count)).to eq(before_counts)
    sd_membership.update!(availability: 'unavailable')
    expect(JrcServiceDesk::AutomaticRoutingService.new(user_context: sd_context).preview(**input)).to include(eligible_members: 0, proposed_account_user_id: nil)
  end

  it 'rejects a self-fallback and a fixed collaborator from another unit' do
    output['assignment']['fallback_queue_id'] = queue.id
    expect { publisher.call(unit_id: sd_unit.id, kind: 'routing', definition: definition, enabled: true, expected_version: 0) }.to raise_error(ArgumentError)
    output['assignment'].delete('fallback_queue_id')
    other = create(:account_user, account: sd_account)
    create(:jrc_sd_membership, unit: sd_other_unit, account_user: other)
    output['assignment']['account_user_id'] = other.id
    expect { publisher.call(unit_id: sd_unit.id, kind: 'routing', definition: definition, enabled: true, expected_version: 0) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'creates internal tasks, labels and notes through native commands exactly once' do
    label = create(:label, account: sd_account, title: 'synthetic-route')
    output.merge!('label_ids' => [label.id], 'task' => { 'title' => 'Synthetic first action', 'description' => 'Internal only' }, 'internal_note' => 'Synthetic internal instruction')
    publisher.call(unit_id: sd_unit.id, kind: 'routing', definition: definition, enabled: true, expected_version: 0)
    ticket = workflow.call(unit_id: sd_unit.id, attributes: sd_create_attributes, idempotency_key: 'actions-once')
    replay = workflow.call(unit_id: sd_unit.id, attributes: sd_create_attributes, idempotency_key: 'actions-once')
    expect(replay.id).to eq(ticket.id)
    expect(ticket.reload.label_list).to contain_exactly(label.title)
    expect(sd_contact.reload.label_list).to be_empty
    expect(ticket.ticket_tasks.count).to eq(1)
    expect(ticket.ticket_tasks.first.visibility).to eq('internal')
    expect(ticket.ticket_notes.count).to eq(1)
    expect(ticket.ticket_notes.first.visibility).to eq('internal')
    expect(Message.count).to eq(0)
    expect(JrcServiceDesk::NotificationDelivery.count).to eq(0)
  end

  it 'keeps idempotent creation valid after an explicitly published service classification' do
    classified = JrcServiceDesk::CreateServiceDefinitionService.new(user_context: sd_context).call(unit_id: sd_unit.id,
      attributes: { name: 'Synthetic classified service', code: 'synthetic-classification', active: true })
    output['classification'] = { 'service_id' => classified.id }
    publisher.call(unit_id: sd_unit.id, kind: 'routing', definition: definition, enabled: true, expected_version: 0)
    ticket = workflow.call(unit_id: sd_unit.id, attributes: sd_create_attributes, idempotency_key: 'classified-service')
    expect(ticket.reload.service).to eq(classified)
    expect(workflow.call(unit_id: sd_unit.id, attributes: sd_create_attributes, idempotency_key: 'classified-service').id).to eq(ticket.id)
    expect(ticket.ticket_events.find_by!(event_type: 'creation_context_recorded').data).to have_key('input_service_id')
  end

  it 'retains native role restrictions, including an idempotent transition replay after revocation' do
    definition = lc_definition
    definition['transitions'].find { |row| row['key'] == 'resolve' }['allowed_account_roles'] = ['administrator']
    lc_publish(definition: definition)
    ticket = sd_ticket
    key = 'restricted-transition'
    lc_execute(ticket, 'resolve', request_key: key)
    sd_account_user.update!(role: :agent)
    expect { lc_execute(ticket, 'resolve', request_key: key) }.to raise_error(Pundit::NotAuthorizedError)
    expect(ticket.lifecycle_transitions.count).to eq(1)
  end
end
