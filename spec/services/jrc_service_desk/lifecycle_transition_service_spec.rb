# frozen_string_literal: true
require 'rails_helper'

RSpec.describe JrcServiceDesk::LifecycleTransitionService, type: :service do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  include ActiveSupport::Testing::TimeHelpers

  it 'persists pause, resume, resolve, close and reopen with actor/version/events and independent reloads' do
    lc_publish
    row = sd_ticket
    pause = lc_execute(row, 'pause', reason_code: 'customer')
    expect(row.reload.status.phase).to eq('waiting')
    expect(row.lifecycle_pauses.last.clocks).to eq([])
    expect(row.lifecycle_pauses.last.started_by_membership_id).to eq(sd_membership.id)
    lc_execute(row, 'resume')
    expect(row.reload.status.phase).to eq('open')
    expect(row.lifecycle_pauses.last.ended_by_membership_id).to eq(sd_membership.id)
    lc_execute(row, 'resolve', note: 'Real persisted resolution note', solution: 'Fixture fix')
    expect(row.reload.status.phase).to eq('resolved')
    lc_execute(row, 'close'); expect(row.reload.status.phase).to eq('closed')
    lc_execute(row, 'reopen'); expect(row.reload.status.phase).to eq('open')
    expect(row.lifecycle_transitions.count).to eq(5)
    expect(row.ticket_events.where(event_type: 'lifecycle_transitioned').count).to eq(5)
    expect(row.sla_cycles.count).to eq(0)
    expect(pause.reload.payload.dig('sla', 'mode')).to eq('not_applicable')
    expect(row.lifecycle_transitions.last.payload.dig('sla', 'reopening', 'sla_cycle')).to eq('continue_cycle')
  end

  it 'requires real note evidence, classification, required solution and configured field value atomically' do
    rules = lc_definition
    requirements = rules['transitions'].find { |r| r['key'] == 'resolve' }['requirements']
    requirements.merge!('note' => true, 'solution' => true, 'evidence' => true, 'classification' => true,
      'fields' => { 'verified' => { 'label' => 'Verified', 'type' => 'boolean', 'required' => true, 'equals' => true } })
    lc_publish(definition: rules)
    row = sd_ticket
    expect { lc_execute(row, 'resolve') }.to raise_error(ArgumentError)
    expect(row.reload.lifecycle_policy_version_id).to be_nil
    row.update!(category: create(:jrc_sd_category, unit: sd_unit))
    note = JrcServiceDesk::AddNoteService.new(user_context: sd_context).call(ticket_id: row.id, attributes: { body: 'Evidence note' }, idempotency_key: 'evidence-note')
    # Verify AddNoteService return contract through the persisted relation.
    note = row.ticket_notes.last
    params = { note: 'Reviewed', solution: 'Fixed', evidence_note_ids: [note.id], fields: { verified: true } }
    event = lc_execute(row, 'resolve', params)
    expect(row.reload.status.phase).to eq('resolved')
    expect(event.payload).to include('solution' => 'Fixed', 'evidence_note_ids' => [note.id])
  end

  it 'rejects evidence from another ticket and preserves the old state' do
    rules = lc_definition; rules['transitions'].find { |r| r['key'] == 'resolve' }['requirements']['evidence'] = true
    lc_publish(definition: rules)
    row = sd_ticket; other = sd_ticket
    JrcServiceDesk::AddNoteService.new(user_context: sd_context).call(ticket_id: other.id, attributes: { body: 'Other evidence' }, idempotency_key: 'other-evidence')
    expect { lc_execute(row, 'resolve', evidence_note_ids: [other.ticket_notes.last.id]) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(row.reload.status.phase).to eq('open')
    expect(row.lifecycle_transitions.count).to eq(0)
  end

  it 'replays the same intent exactly once and rejects changed payload or stale expected version' do
    policy = lc_publish; row = sd_ticket
    data = { rule_key: 'pause', reason_code: 'customer', expected_lock_version: row.lock_version, expected_policy_version_id: policy.current_version_id }
    command = described_class.new(user_context: sd_context)
    first = command.call(ticket_id: row.id, attributes: data, idempotency_key: 'same-transition')
    again = command.call(ticket_id: row.id, attributes: data, idempotency_key: 'same-transition')
    expect(again.id).to eq(first.id)
    expect(row.lifecycle_pauses.count).to eq(1)
    expect { command.call(ticket_id: row.id, attributes: data.merge(note: 'Changed'), idempotency_key: 'same-transition') }.to raise_error(JrcServiceDesk::IdempotencyConflict)
    expect { command.call(ticket_id: row.id, attributes: data, idempotency_key: 'different-transition') }.to raise_error(ActiveRecord::StaleObjectError)
  end

  %w[deny require_new_ticket].each do |expiry|
    it "denies expired reopen with #{expiry} without creating another ticket" do
      rules = lc_definition; rules['reopen']['window_seconds'] = 60; rules['reopen']['expired'] = expiry
      lc_publish(definition: rules); row = sd_ticket
      lc_execute(row, 'resolve')
      travel 61.seconds do
        expect { expect { lc_execute(row, 'reopen') }.to raise_error(ArgumentError) }.not_to change(JrcServiceDesk::Ticket, :count)
      end
      expect(row.reload.status.phase).to eq('resolved')
    end
  end

  it 'cancels only through an allowed rule and records the original phase' do
    lc_publish; row = sd_ticket
    result = lc_execute(row, 'cancel', note: 'Requested cancellation')
    expect(row.reload.status.phase).to eq('cancelled')
    expect(result.payload.values_at('from_phase', 'to_phase')).to eq(%w[open cancelled])
    expect { lc_execute(row, 'resume') }.to raise_error(ArgumentError)
  end

  it 'rejects revoked grant, disabled flag, another Account and a unit without grant even for admin' do
    lc_publish; row = sd_ticket
    sd_as_admin!
    foreign = create(:jrc_sd_ticket, unit: sd_foreign_unit)
    expect { lc_execute(foreign, 'resolve') }.to raise_error(ActiveRecord::RecordNotFound)
    sd_membership.update!(active: false)
    expect { lc_execute(row, 'resolve') }.to raise_error(ActiveRecord::RecordNotFound)
    sd_membership.update!(active: true)
    sd_account.disable_features!('jrc_service_desk')
    expect { lc_execute(row, 'resolve') }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'rolls back status, pause, policy pin and transition when the historical event fails' do
    lc_publish; row = sd_ticket
    allow(JrcServiceDesk::TicketEvent).to receive(:create!).and_call_original
    allow(JrcServiceDesk::TicketEvent).to receive(:create!).with(hash_including(event_type: 'lifecycle_transitioned')).and_raise(ActiveRecord::StatementInvalid)
    expect { lc_execute(row, 'pause', reason_code: 'customer') }.to raise_error(ActiveRecord::StatementInvalid)
    expect(row.reload.status.phase).to eq('open')
    expect(row.lifecycle_policy_version_id).to be_nil
    expect(row.lifecycle_transitions.count).to eq(0)
    expect(row.lifecycle_pauses.count).to eq(0)
  end

  it 'rejects IDs passed as attributes and detects status semantics changed after publication' do
    lc_publish; row = sd_ticket
    expect { lc_execute(row, 'resolve', account_id: sd_foreign_account.id) }.to raise_error(ArgumentError)
    expect { lc_statuses[:resolved].update!(phase: 'closed') }.to raise_error(ActiveRecord::RecordInvalid)
    # Simulate privileged SQL bypassing the model guard; execution must still reject the drift.
    lc_statuses[:resolved].reload.update_column(:phase, 'closed')
    expect { lc_execute(row, 'resolve') }.to raise_error(ArgumentError)
    expect(row.reload.status.phase).to eq('open')
  end
end
