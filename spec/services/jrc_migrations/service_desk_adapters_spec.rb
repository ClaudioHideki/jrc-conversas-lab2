require 'rails_helper'

# Integration coverage groups several adapters under the Migration Center feature.
RSpec.describe JrcMigrations::Adapters::ServiceDeskTicket do # rubocop:disable RSpec/SpecFilePathFormat
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:unit) { create(:jrc_sd_unit, operator_company: create(:jrc_sd_operator_company, account: account)) }
  let(:membership) { create(:jrc_sd_membership, unit: unit, account_user: account.account_users.find_by!(user: admin)) }
  let(:requester) { create(:contact, account: account) }
  let(:closed_status) { create(:jrc_sd_status, unit: unit, initial: false, phase: 'closed') }
  let(:priority) { create(:jrc_sd_priority, unit: unit) }
  let(:dates) { { 'created_at' => '2021-01-02T12:00:00Z', 'updated_at' => '2024-02-03T12:00:00Z' } }
  let(:ticket_row) do
    dates.merge('legacy_id' => 'ticket-1', 'unit_id' => unit.id, 'requester_id' => requester.id, 'status_id' => closed_status.id,
                'priority_id' => priority.id, 'created_by_membership_id' => membership.id, 'title' => 'Historical closed ticket',
                'description' => 'Source description', 'opened_at' => '2021-01-02T12:00:00Z', 'origin_channel' => 'legacy',
                'idempotency_key' => 'source-ticket-1', 'request_fingerprint' => 'a' * 64)
  end

  def preview(domain, row)
    batch = JrcMigrations::Stage.new(account: account, user: admin).call(source: 'fixture', domain: domain, rows: [row], mapping: {})
    JrcMigrations::Preview.new(batch: batch, user: admin).call
    batch
  end

  def import(domain, row)
    batch = preview(domain, row)
    expect(batch.items.first.decision).to eq('create')
    JrcMigrations::Execute.new(batch: batch, user: admin).call
    expect(batch.items.reload.first.status).to eq('applied')
    batch.items.first.target_id
  end

  it 'imports a closed ticket with original dates, without weakening ordinary creation or emitting signals' do
    batch = preview('service_desk_tickets', ticket_row)
    expect(batch.items.first.decision).to eq('create')
    expect(Rails.configuration.dispatcher).not_to receive(:dispatch)
    expect { JrcMigrations::Execute.new(batch: batch, user: admin).call }.not_to have_enqueued_job
    ticket = JrcServiceDesk::Ticket.find(batch.items.reload.first.target_id)
    expect(ticket).to have_attributes(status_id: closed_status.id, requester_id: requester.id, created_by_membership_id: membership.id,
                                      opened_at: Time.iso8601(ticket_row['opened_at']), created_at: Time.iso8601(dates['created_at']))
    native = build(:jrc_sd_ticket, unit: unit, status: closed_status, requester: requester,
                                   priority: priority, created_by_membership: membership)
    expect(native).not_to be_valid
    expect(native.errors[:status]).to include('must be an explicitly configured active initial status')
  end

  it 'retains mandatory description and rejects cross-unit authors instead of weakening domain validation' do
    expect(preview('service_desk_tickets', ticket_row.merge('description' => nil)).items.first.decision).to eq('reject')
    other_unit = create(:jrc_sd_unit, operator_company: unit.operator_company)
    other = create(:jrc_sd_membership, unit: other_unit)
    expect(preview('service_desk_tickets', ticket_row.merge('created_by_membership_id' => other.id)).items.first.decision).to eq('reject')
  end

  it 'retains an inactive historical author and status without reactivating their operational grant' do
    membership.update!(active: false)
    closed_status.update!(active: false)
    ticket = JrcServiceDesk::Ticket.find(import('service_desk_tickets', ticket_row))
    expect(ticket).to have_attributes(status_id: closed_status.id, created_by_membership_id: membership.id)
    expect(membership.reload.active).to be(false)
    expect(closed_status.reload.active).to be(false)
  end

  it 'keeps native ownership immutable when applying a historical delta' do
    ticket = JrcServiceDesk::Ticket.find(import('service_desk_tickets', ticket_row))
    changed = ticket_row.merge('origin_channel' => 'changed-origin', 'updated_at' => '2025-01-01T12:00:00Z')
    expect(preview('service_desk_tickets', changed).items.first.decision).to eq('reject')
    expect(ticket.reload.origin_channel).to eq('legacy')
  end

  it 'imports append-only timeline events, keeps source time and never schedules notifications' do
    ticket_id = import('service_desk_tickets', ticket_row)
    event_row = dates.merge('legacy_id' => 'event-1', 'unit_id' => unit.id, 'ticket_legacy_id' => 'ticket-1',
                            'actor_membership_id' => membership.id, 'event_type' => 'first_response_observed',
                            'visibility' => 'internal', 'data' => { 'source_note' => 'Historic response' })
    expect(JrcServiceDesk::NotificationEventJob).not_to receive(:perform_later)
    expect(JrcRelationship::SurveyResponseEventJob).not_to receive(:perform_later)
    event = JrcServiceDesk::TicketEvent.find(import('service_desk_events', event_row))
    expect(event.ticket_id).to eq(ticket_id)
    expect(event.created_at).to eq(Time.iso8601(dates['created_at']))
    changed = event_row.merge('updated_at' => '2025-01-01T12:00:00Z', 'data' => { 'source_note' => 'Altered history' })
    item = preview('service_desk_events', changed).items.first
    expect(item).to have_attributes(decision: 'reject', error_code: 'APPEND_ONLY_DESTINATION')
    expect(event.reload.data).to eq('source_note' => 'Historic response')
  end

  it 'preserves SLA source conditions, hash and historic outcome without recalculating deadlines' do
    ticket = JrcServiceDesk::Ticket.find(import('service_desk_tickets', ticket_row))
    source_snapshot = build(:jrc_sd_snapshot, ticket: ticket, captured_at: Time.iso8601(dates['created_at']),
                                              applied_at: Time.iso8601(dates['created_at']))
    snapshot_row = source_snapshot.attributes.except('id', 'account_id', 'created_at').merge(dates).merge('legacy_id' => 'sla-1')
    snapshot_row['captured_at'] = source_snapshot.captured_at.iso8601
    snapshot_row['applied_at'] = source_snapshot.applied_at.iso8601
    snapshot_id = import('service_desk_sla_snapshots', snapshot_row)
    milestone_row = dates.merge('legacy_id' => 'milestone-1', 'unit_id' => unit.id, 'ticket_id' => ticket.id,
                                'sla_snapshot_legacy_id' => 'sla-1', 'kind' => 'resolution', 'due_at' => '2021-01-03T12:00:00Z',
                                'calculated_at' => '2021-01-02T12:00:00Z', 'calculator_version' => 'legacy-v2',
                                'achieved_at' => '2021-01-04T12:00:00Z')
    milestone = JrcServiceDesk::SlaMilestone.find(import('service_desk_sla_milestones', milestone_row))
    expect(milestone.sla_snapshot_id).to eq(snapshot_id)
    expect(milestone.met?).to be(false)
    expect(milestone.due_at).to eq(Time.iso8601(milestone_row['due_at']))
    expect(JrcServiceDesk::SlaSnapshot.find(snapshot_id).payload_digest).to eq(source_snapshot.payload_digest)
    expect(JrcMigrations::Mapping.find_by!(domain: 'service_desk_sla_snapshots', target_id: snapshot_id).accepted_at).to be_nil
  end

  it 'rejects a snapshot whose supplied hash disagrees and a milestone from another ticket' do
    ticket = create(:jrc_sd_ticket, unit: unit)
    source_snapshot = build(:jrc_sd_snapshot, ticket: ticket)
    row = source_snapshot.attributes.except('id', 'account_id', 'created_at').merge(dates).merge('legacy_id' => 'bad-sla',
                                                                                                 'payload_digest' => 'f' * 64)
    row['captured_at'] = source_snapshot.captured_at.iso8601
    row['applied_at'] = source_snapshot.applied_at.iso8601
    expect(preview('service_desk_sla_snapshots', row).items.first.decision).to eq('reject')
    snapshot = create(:jrc_sd_snapshot, ticket: ticket)
    other_ticket = create(:jrc_sd_ticket, unit: unit, status: ticket.status, priority: ticket.priority,
                                          created_by_membership: ticket.created_by_membership)
    row = dates.merge('legacy_id' => 'bad-milestone', 'unit_id' => unit.id, 'ticket_id' => other_ticket.id,
                      'sla_snapshot_id' => snapshot.id, 'kind' => 'resolution')
    expect(preview('service_desk_sla_milestones', row).items.first.decision).to eq('reject')
  end
end
