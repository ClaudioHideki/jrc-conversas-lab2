# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk::RecordSlaSnapshotService do
  include_context 'JRC Service Desk domain'
  subject(:service) { described_class.new(user_context: sd_context) }
  let(:ticket) { sd_ticket }

  it 'does not allow an ordinary agent to write contract/SLA conditions' do
    expect { service.call(ticket_id: ticket.id, attributes: sd_snapshot_attributes) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it 'stores explicit conditions and creates two pending, not calculated, milestones' do
    sd_as_admin!
    snapshot = service.call(ticket_id: ticket.id, attributes: sd_snapshot_attributes)
    expect(snapshot.version).to eq(1)
    expect(snapshot.sla_milestones.pluck(:kind)).to match_array(%w[first_response resolution])
    expect(snapshot.sla_milestones.all?(&:calculation_pending?)).to be(true)
    expect(snapshot.sla_milestones.pluck(:due_at, :achieved_at)).to eq([[nil, nil], [nil, nil]])
  end

  it 'is idempotent for the same captured evidence' do
    sd_as_admin!
    first = service.call(ticket_id: ticket.id, attributes: sd_snapshot_attributes)
    again = service.call(ticket_id: ticket.id, attributes: sd_snapshot_attributes)
    expect(again.id).to eq(first.id)
    expect(ticket.sla_snapshots.count).to eq(1)
    expect(ticket.ticket_events.where(event_type: 'sla_snapshot_recorded').count).to eq(1)
  end

  it 'creates a new version without rewriting previously applied conditions' do
    sd_as_admin!
    first = service.call(ticket_id: ticket.id, attributes: sd_snapshot_attributes)
    original = first.attributes.deep_dup
    second = service.call(ticket_id: ticket.id, attributes: sd_snapshot_attributes.merge(source_version: 'v2', contract_conditions: { coverage: 'new-test' }))
    expect(second.version).to eq(2)
    expect(first.reload.attributes).to eq(original)
  end

  it 'requires explicit timezone in captured_at and never chooses a local fallback' do
    sd_as_admin!
    expect do
      service.call(ticket_id: ticket.id, attributes: sd_snapshot_attributes.merge(captured_at: '2026-09-25T10:00:00'))
    end.to raise_error(ArgumentError)
  end

  it 'rejects credential fields and does not persist a partial snapshot' do
    sd_as_admin!
    attrs = sd_snapshot_attributes.merge(contract_conditions: { password: 'fixture-only' })
    expect do
      expect { service.call(ticket_id: ticket.id, attributes: attrs) }.to raise_error(ActiveRecord::RecordInvalid)
    end.not_to change(JrcServiceDesk::SlaSnapshot, :count)
  end

  it 'rejects a user-supplied local version or calculated deadline' do
    sd_as_admin!
    expect { service.call(ticket_id: ticket.id, attributes: sd_snapshot_attributes.merge(version: 9)) }.to raise_error(ArgumentError)
    expect { service.call(ticket_id: ticket.id, attributes: sd_snapshot_attributes.merge(due_at: Time.current)) }.to raise_error(ArgumentError)
  end

  it 'does not bypass the unit boundary for an administrator' do
    sd_as_admin!
    other = create(:jrc_sd_ticket, unit: sd_other_unit)
    expect { service.call(ticket_id: other.id, attributes: sd_snapshot_attributes) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'rejects coercible non-text provenance and non-object conditions' do
    sd_as_admin!
    expect { service.call(ticket_id: ticket.id, attributes: sd_snapshot_attributes.merge(source_system: ['not-text'])) }.to raise_error(ArgumentError)
    expect { service.call(ticket_id: ticket.id, attributes: sd_snapshot_attributes.merge(calendar_conditions: [])) }.to raise_error(ArgumentError)
  end

  it 'deduplicates the same capture instant expressed in different timezone offsets' do
    sd_as_admin!
    first = service.call(ticket_id: ticket.id, attributes: sd_snapshot_attributes)
    again = service.call(ticket_id: ticket.id, attributes: sd_snapshot_attributes.merge(captured_at: '2026-09-25T07:00:00-03:00'))
    expect(again.id).to eq(first.id)
    expect(first.reload.expected_digest).to eq(first.payload_digest)
  end

end
