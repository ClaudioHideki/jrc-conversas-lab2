# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures

  def interaction(ticket, values, key: SecureRandom.uuid)
    attributes = { body: 'Test interaction' }.merge(values)
    context = JrcServiceDesk::OperationalContext.new(sd_context)
    receipt = JrcServiceDesk::InteractionPreview.new(ticket: ticket, context: context).call(attributes: attributes).fetch(:receipt)
    JrcServiceDesk::AddNoteService.new(user_context: sd_context).call(ticket_id: ticket.id,
                                                                      attributes: attributes, preview_receipt: receipt, idempotency_key: key)
  end

  def task(ticket, values = {})
    JrcServiceDesk::CreateTaskService.new(user_context: sd_context).call(ticket_id: ticket.id,
                                                                         attributes: {
                                                                           title: 'Verify restoration', checklist: [{ 'title' => 'Verify service',
                                                                                                                      'done' => false }]
                                                                         }.merge(values),
                                                                         idempotency_key: SecureRandom.uuid)
  end

  it 'preserves legacy internal interaction fingerprints and replay' do
    row = sd_ticket
    first = interaction(row, {}, key: 'legacy-replay')
    expect(first.request_fingerprint).to eq(JrcServiceDesk::CanonicalJson.digest('body' => 'Test interaction'))
    expect(interaction(row, {}, key: 'legacy-replay').id).to eq(first.id)
    expect(row.ticket_notes.count).to eq(1)
  end

  %w[customer public_without_notification].each do |visibility|
    it "requires an explicit customer publication grant for #{visibility}" do
      expect { interaction(sd_ticket, { visibility: visibility }) }.to raise_error(Pundit::NotAuthorizedError)
      expect(JrcServiceDesk::TicketNote.count).to eq(0)
    end
  end

  it 'publishes a new immutable audience version and retains its previous content' do
    sd_as_admin!
    row = sd_ticket
    original = interaction(row, {})
    published = interaction(row,
                            { visibility: 'public_without_notification', previous_note_id: original.id,
                              publication_reason: 'Customer approved publication' })
    expect(published.previous_note_id).to eq(original.id)
    expect(original.reload.visibility).to eq('internal')
    expect { original.update!(visibility: 'customer') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect(row.ticket_events.last.event_type).to eq('interaction_republished')
    expect(JrcServiceDesk::NotificationDelivery.count).to eq(0)
  end

  it 'rejects republication without reason without changing original or history' do
    sd_as_admin!
    row = sd_ticket
    original = interaction(row, {})
    expect { interaction(row, { visibility: 'customer', previous_note_id: original.id }) }.to raise_error(ArgumentError)
    expect(row.ticket_notes.count).to eq(1)
    expect(row.ticket_events.count).to eq(1)
  end

  it 'never permits an external delivery request for an internal or public silent interaction' do
    %w[internal public_without_notification].each do |visibility|
      expect { interaction(sd_ticket, { visibility: visibility, notification_channels: ['email'] }) }.to raise_error(ArgumentError)
    end
    expect(JrcServiceDesk::NotificationDelivery.count).to eq(0)
  end

  it 'filters technical notes and their events again after native team membership revocation' do
    team = create(:team, account: sd_account)
    team_member = create(:team_member, team: team, user: sd_user)
    row = sd_ticket(team: team)
    note = interaction(row, { visibility: 'technical_team', audience_team_id: team.id })
    expect(JrcServiceDesk::TicketNotePolicy.new(sd_context, note).show?).to be(true)
    team_member.destroy!
    expect(JrcServiceDesk::TicketNotePolicy.new(sd_context, note.reload).show?).to be(false)
    expect(JrcServiceDesk::TicketNotePolicy::Scope.new(sd_context, JrcServiceDesk::TicketNote).resolve).not_to include(note)
    expect(JrcServiceDesk::TicketEventPolicy::Scope.new(sd_context, JrcServiceDesk::TicketEvent).resolve.where(ticket_id: row.id)).to be_empty
  end

  it 'rejects a technical publication to a team other than the current ticket team' do
    sd_as_admin!
    team = create(:team, account: sd_account)
    create(:team_member, team: team, user: sd_user)
    expect { interaction(sd_ticket, { visibility: 'technical_team', audience_team_id: team.id }) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'filters task visibility through the same technical audience scope' do
    team = create(:team, account: sd_account)
    member = create(:team_member, team: team, user: sd_user)
    row = task(sd_ticket(team: team), visibility: 'technical_team', audience_team_id: team.id)
    member.destroy!
    expect(JrcServiceDesk::TicketTaskPolicy::Scope.new(sd_context, JrcServiceDesk::TicketTask).resolve).not_to include(row)
  end

  it 'prevents task completion with unchecked items and confirms the persisted checklist' do
    ticket = sd_ticket
    row = task(ticket)
    service = JrcServiceDesk::UpdateTaskService.new(user_context: sd_context)
    expect { service.call(ticket_id: ticket.id, task_id: row.id, attributes: { status: 'completed' }, expected_lock_version: row.lock_version) }
      .to raise_error(ActiveRecord::RecordInvalid)
    expect(row.reload.status).to eq('open')
    result = service.call(ticket_id: ticket.id, task_id: row.id,
                          attributes: { status: 'completed', checklist: [{ 'title' => 'Verify service', 'done' => true }] },
                          expected_lock_version: row.lock_version)
    expect(result.reload.completed_at).to be_present
    expect(result.status).to eq('completed')
    expect(ticket.ticket_events.last.event_type).to eq('task_updated')
  end

  it 'rejects stale task updates and does not overwrite the confirmed checklist' do
    ticket = sd_ticket
    row = task(ticket)
    old_version = row.lock_version
    row.update!(priority: 'high')
    expect do
      JrcServiceDesk::UpdateTaskService.new(user_context: sd_context).call(ticket_id: ticket.id, task_id: row.id,
                                                                           attributes: { priority: 'low' }, expected_lock_version: old_version)
    end.to raise_error(ActiveRecord::StaleObjectError)
    expect(row.reload.priority).to eq('high')
  end

  it 'requires a real assigned approver, preserves rejection comments and denies another administrator' do
    ticket = sd_ticket
    approver = create(:account_user, account: sd_account, role: :agent)
    grant = create(:jrc_sd_membership, unit: sd_unit, account_user: approver)
    row = JrcServiceDesk::CreateApprovalService.new(user_context: sd_context).call(
      ticket_id: ticket.id,
      attributes: { title: 'Approve restoration', approver_account_user_id: approver.id, due_at: 1.day.from_now.iso8601 },
      idempotency_key: 'approval'
    )
    sd_as_admin!
    expect do
      JrcServiceDesk::DecideApprovalService.new(user_context: sd_context).call(
        ticket_id: ticket.id, approval_id: row.id, attributes: { status: 'approved' }, expected_lock_version: row.lock_version
      )
    end.to raise_error(Pundit::NotAuthorizedError)
    context = { account: sd_account, user: approver.user, account_user: approver }
    service = JrcServiceDesk::DecideApprovalService.new(user_context: context)
    expect { service.call(ticket_id: ticket.id, approval_id: row.id, attributes: { status: 'rejected' }, expected_lock_version: row.lock_version) }
      .to raise_error(ActiveRecord::RecordInvalid)
    service.call(ticket_id: ticket.id, approval_id: row.id, attributes: { status: 'rejected', comment: 'Evidence incomplete' },
                 expected_lock_version: row.lock_version)
    expect(row.reload.comment).to eq('Evidence incomplete')
    expect(row.decided_at).to be_present
    grant.update!(active: false)
    expect(JrcServiceDesk::TicketApprovalPolicy.new(context, row).show?).to be(false)
  end

  it 'links one incident to scoped tickets atomically and never imports a foreign unit ticket' do
    sd_as_admin!
    row = sd_ticket
    foreign = sd_ticket(unit: sd_other_unit, status: create(:jrc_sd_status, unit: sd_other_unit),
                        priority: create(:jrc_sd_priority, unit: sd_other_unit),
                        created_by_membership: create(:jrc_sd_membership, unit: sd_other_unit, account_user: sd_account_user))
    service = JrcServiceDesk::CreateIncidentService.new(user_context: sd_context)
    expect do
      service.call(unit_id: sd_unit.id, attributes: { title: 'Outage', severity: 'high', ticket_ids: [row.id, foreign.id] },
                   idempotency_key: 'foreign-incident')
    end
      .to raise_error(ActiveRecord::RecordNotFound)
    expect(row.reload.incident_id).to be_nil
    incident = service.call(unit_id: sd_unit.id, attributes: { title: 'Outage', severity: 'high', ticket_ids: [row.id] }, idempotency_key: 'incident')
    expect(row.reload.incident_id).to eq(incident.id)
    expect(incident.primary_ticket_id).to eq(row.id)
  end

  it 'requires availability and configured capacity only for claim, preserving manual assignment' do
    row = sd_ticket
    expect { JrcServiceDesk::ClaimNextService.new(user_context: sd_context).call(unit_id: sd_unit.id, idempotency_key: 'unavailable-claim') }
      .to raise_error(JrcServiceDesk::LifecycleDependencyError)
    JrcServiceDesk::AssignTicketService.new(user_context: sd_context).call(
      ticket_id: row.id, attributes: { assignee_account_user_id: sd_account_user.id }, expected_lock_version: row.lock_version
    )
    expect(row.reload.assignee_membership_id).to eq(sd_membership.id)
  end

  it 'claims once with replay and enforces active capacity before selecting another ticket' do
    sd_membership.update!(availability: 'available', capacity: 1)
    first = sd_ticket
    second = sd_ticket
    service = JrcServiceDesk::ClaimNextService.new(user_context: sd_context)
    expect(service.call(unit_id: sd_unit.id, idempotency_key: 'claim').id).to eq(first.id)
    expect(service.call(unit_id: sd_unit.id, idempotency_key: 'claim').id).to eq(first.id)
    expect { service.call(unit_id: sd_unit.id, idempotency_key: 'next-claim') }.to raise_error(JrcServiceDesk::LifecycleDependencyError)
    expect(second.reload.assignee_membership_id).to be_nil
    expect(first.ticket_events.where(event_type: 'ticket_claimed').count).to eq(1)
  end

  it 'does not claim a ticket requiring a skill absent from the agent profile' do
    sd_membership.update!(availability: 'available', capacity: 3, skills: ['basic'])
    queue = create(:jrc_sd_queue, unit: sd_unit, required_skills: ['fiber'])
    row = sd_ticket(queue: queue)
    expect(JrcServiceDesk::ClaimNextService.new(user_context: sd_context).call(unit_id: sd_unit.id, idempotency_key: 'skills')).to be_nil
    expect(row.reload.assignee_membership_id).to be_nil
  end

  it 'routes only enabled queues with eligible native operators and explicit capacity' do
    sd_membership.update!(availability: 'available', capacity: 3, skills: ['fiber'])
    queue = create(:jrc_sd_queue, unit: sd_unit, distribution_mode: 'skill', required_skills: ['fiber'])
    row = JrcServiceDesk::CreateTicketWorkflowService.new(user_context: sd_context).call(
      unit_id: sd_unit.id, attributes: sd_create_attributes.merge(queue_id: queue.id), idempotency_key: 'auto-route'
    )
    expect(row.reload.assignee_membership_id).to eq(sd_membership.id)
    expect(row.ticket_events.where(event_type: 'ticket_auto_routed').count).to eq(1)
  end

  it 'tracks real queue OLA intervals without changing customer SLA snapshots' do
    queue = create(:jrc_sd_queue, unit: sd_unit, ola_budget_seconds: 600, ola_time_basis: 'calendar', ola_pause_waiting: true)
    row = sd_ticket(queue: queue)
    start = Time.current
    JrcServiceDesk::OlaTracker.sync!(row, now: start)
    clock = row.ola_clocks.first
    waiting = create(:jrc_sd_status, unit: sd_unit, initial: false, phase: 'waiting')
    row.update!(status: waiting)
    JrcServiceDesk::OlaTracker.sync!(row, now: start + 60)
    expect(clock.reload.state).to eq('paused')
    expect(clock.elapsed_seconds).to be_within(0.001).of(60)
    row.update!(status: sd_status)
    JrcServiceDesk::OlaTracker.sync!(row, now: start + 360)
    expect(clock.reload.due_at).to be_within(0.001).of(start + 900)
    expect(row.sla_snapshots).to be_empty
    expect(row.sla_cycles).to be_empty
  end

  it 'fails explicitly instead of fabricating a business OLA calendar' do
    queue = create(:jrc_sd_queue, unit: sd_unit, ola_budget_seconds: 600, ola_time_basis: 'business')
    row = sd_ticket(queue: queue)
    expect { JrcServiceDesk::OlaTracker.sync!(row) }.to raise_error(JrcServiceDesk::LifecycleDependencyError)
    expect(row.ola_clocks).to be_empty
  end

  it 'requires catalogue fields and retains real service answers' do
    service = JrcServiceDesk::Service.create!(account: sd_account, unit: sd_unit, code: 'catalog', name: 'Fiber', active: true,
                                              form_fields: [{ 'key' => 'circuit', 'label' => 'Circuit', 'type' => 'text', 'required' => true }])
    command = JrcServiceDesk::CreateTicketService.new(user_context: sd_context)
    expect { command.call(unit_id: sd_unit.id, attributes: sd_create_attributes, service_id: service.id, idempotency_key: 'missing-circuit') }
      .to raise_error(ActiveRecord::RecordInvalid)
    row = command.call(unit_id: sd_unit.id, attributes: sd_create_attributes.merge(service_fields: { 'circuit' => 'TEST-123' }),
                       service_id: service.id, idempotency_key: 'circuit')
    expect(row.reload.service_fields).to eq('circuit' => 'TEST-123')
  end
end
