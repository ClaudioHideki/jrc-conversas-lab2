# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk::AssignmentEligibility do
  include_context 'JRC Service Desk domain'
  let(:queue) { create(:jrc_sd_queue, unit: sd_unit, distribution_mode: 'round_robin') }
  let(:ticket) { sd_ticket(queue: queue) }
  let(:routing) { JrcServiceDesk::AutomaticRoutingService.new(user_context: sd_context) }

  before do
    sd_account_user.update!(availability: :online)
    sd_membership.update!(availability: 'available', capacity: 2)
    allow(OnlineStatusTracker).to receive(:effective_presence).with(sd_account.id).and_return(user_ids: [sd_user.id], reason: nil)
  end

  it 'excludes an opted-out account member without changing native teams, availability or historical assignments and permits manual assignment' do
    team = create(:team, account: sd_account)
    create(:team_member, team: team, user: sd_user)
    existing = sd_ticket(assignee_membership: sd_membership)
    sd_account_user.update!(auto_assignment_enabled: false)
    routing.call(ticket_id: ticket.id)
    expect(ticket.reload.assignee_membership_id).to be_nil
    expect(existing.reload.assignee_membership_id).to eq(sd_membership.id)
    expect(sd_account_user.reload.availability).to eq('online')
    expect(TeamMember.where(user: sd_user, team: team)).to exist
    JrcServiceDesk::AssignTicketService.new(user_context: sd_context).call(ticket_id: ticket.id,
      attributes: { assignee_account_user_id: sd_account_user.id }, expected_lock_version: ticket.lock_version)
    expect(ticket.reload.assignee_membership_id).to eq(sd_membership.id)
  end

  it 'requires fresh effective presence even when availability is configured online and fails closed on Redis unavailability' do
    allow(OnlineStatusTracker).to receive(:effective_presence).and_return(user_ids: [], reason: nil)
    expect(described_class.new(membership: sd_membership, ticket: ticket).reason).to eq('no_effective_presence')
    routing.call(ticket_id: ticket.id)
    expect(ticket.reload.assignee_membership_id).to be_nil
    allow(OnlineStatusTracker).to receive(:effective_presence).and_return(user_ids: [], reason: 'redis_presence_unavailable')
    expect(described_class.new(membership: sd_membership, ticket: ticket).reason).to eq('redis_presence_unavailable')
  end

  it 'rechecks the individual flag immediately before persistence after a candidate was selected' do
    allow(routing).to receive(:select_candidate).and_wrap_original do |original, *args, **kwargs|
      chosen = original.call(*args, **kwargs)
      sd_account_user.update!(auto_assignment_enabled: false)
      chosen
    end
    routing.call(ticket_id: ticket.id)
    expect(ticket.reload.assignee_membership_id).to be_nil
    expect(ticket.ticket_events.where(event_type: 'ticket_auto_routed')).to be_empty
  end

  it 'rechecks effective presence at the final write and never double-assigns a ticket on repeated jobs' do
    allow(OnlineStatusTracker).to receive(:effective_presence)
      .and_return({ user_ids: [sd_user.id], reason: nil }, { user_ids: [], reason: nil })
    routing.call(ticket_id: ticket.id)
    expect(ticket.reload.assignee_membership_id).to be_nil
    allow(OnlineStatusTracker).to receive(:effective_presence).and_return(user_ids: [sd_user.id], reason: nil)
    2.times { routing.call(ticket_id: ticket.id) }
    expect(ticket.reload.assignee_membership_id).to eq(sd_membership.id)
    expect(ticket.ticket_events.where(event_type: 'ticket_auto_routed').count).to eq(1)
  end

  it 'handles a new priority SLA event without claiming an older historical ticket' do
    queue.update!(distribution_mode: 'priority_sla')
    old = sd_ticket(queue: queue, opened_at: 2.months.ago, priority: create(:jrc_sd_priority, unit: sd_unit, position: 0))
    routing.call(ticket_id: ticket.id)
    expect(ticket.reload.assignee_membership_id).to eq(sd_membership.id)
    expect(old.reload.assignee_membership_id).to be_nil
    expect(old.ticket_events).to be_empty
  end

  it 'keeps manual permission separate from automatic eligibility and checks queue and skill restrictions' do
    sd_membership.update!(manual_assignment_enabled: false)
    routing.call(ticket_id: ticket.id)
    expect(ticket.reload.assignee_membership_id).to eq(sd_membership.id)
    other = sd_ticket(queue: queue)
    expect do
      JrcServiceDesk::AssignTicketService.new(user_context: sd_context).call(ticket_id: other.id,
        attributes: { assignee_account_user_id: sd_account_user.id }, expected_lock_version: other.lock_version)
    end.to raise_error(ActiveRecord::RecordNotFound)
    queue.update!(required_skills: ['synthetic-skill'])
    expect(described_class.new(membership: sd_membership, ticket: other).reason).to eq('skills_missing')
  end

  it 'applies the same exclusion to an automatic catalogue default without blocking an explicitly authorized manual choice' do
    service = JrcServiceDesk::Service.create!(account: sd_account, unit: sd_unit, name: 'Synthetic service', code: 'eligibility-default',
      active: true, default_queue: queue, default_assignee_membership: sd_membership)
    sd_account_user.update!(auto_assignment_enabled: false)
    created = JrcServiceDesk::CreateTicketService.new(user_context: sd_context).call(unit_id: sd_unit.id, service_id: service.id,
      attributes: sd_create_attributes, idempotency_key: 'excluded-default')
    expect(created.assignee_membership_id).to be_nil
    manual = JrcServiceDesk::CreateTicketService.new(user_context: sd_context).call(unit_id: sd_unit.id, service_id: service.id,
      attributes: sd_create_attributes.merge(assignee_account_user_id: sd_account_user.id), idempotency_key: 'explicit-manual')
    expect(manual.assignee_membership_id).to eq(sd_membership.id)
  end

  it 'filters manual assignees by the queue team before pagination while retaining an opted-out member' do
    team = create(:team, account: sd_account)
    queue.update!(team: team)
    create(:team_member, team: team, user: sd_user)
    sd_account_user.update!(auto_assignment_enabled: false)
    unrelated = create(:account_user, account: sd_account, role: :agent)
    create(:jrc_sd_membership, unit: sd_unit, account_user: unrelated)
    disabled = create(:account_user, account: sd_account, role: :agent)
    create(:team_member, team: team, user: disabled.user)
    create(:jrc_sd_membership, unit: sd_unit, account_user: disabled, manual_assignment_enabled: false)

    result = JrcServiceDesk::CatalogQuery.new(user_context: sd_context, resource: 'assignees',
      parameters: { unit_id: sd_unit.id, queue_id: queue.id, per_page: 1 }).collection

    expect(result[:meta]).to include(total: 1, per_page: 1)
    expect(result[:items].map(&:account_user_id)).to eq([sd_account_user.id])
  end

  it 'keeps a manual queue unassigned even when its catalogue default is otherwise eligible automatically' do
    queue.update!(distribution_mode: 'manual')
    service = JrcServiceDesk::Service.create!(account: sd_account, unit: sd_unit, name: 'Synthetic manual service',
      code: 'manual-default', active: true, default_queue: queue, default_assignee_membership: sd_membership)
    created = JrcServiceDesk::CreateTicketService.new(user_context: sd_context).call(unit_id: sd_unit.id, service_id: service.id,
      attributes: sd_create_attributes, idempotency_key: 'manual-default-not-automatic')
    expect(created.assignee_membership_id).to be_nil
    JrcServiceDesk::AssignTicketService.new(user_context: sd_context).call(ticket_id: created.id,
      attributes: { assignee_account_user_id: sd_account_user.id }, expected_lock_version: created.lock_version)
    expect(created.reload.assignee_membership_id).to eq(sd_membership.id)
  end
end
