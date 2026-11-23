# frozen_string_literal: true

# Transaction-local persistence shared by two separately authorized commands:
# manual recording and application of a published rule during ticket creation.
# This is not an authorization entry point and accepts no request parameters.
class JrcServiceDesk::SlaSnapshotWriter
  def self.call(snapshot:, actor:)
    ticket = snapshot.ticket
    snapshot.payload_digest = snapshot.expected_digest
    existing = ticket.sla_snapshots.where(account_id: ticket.account_id, unit_id: ticket.unit_id,
                                          payload_digest: snapshot.payload_digest).first
    return existing if existing

    snapshot.version = (ticket.sla_snapshots.maximum(:version) || 0) + 1
    snapshot.save!
    JrcServiceDesk::SlaMilestone::KINDS.each do |kind|
      JrcServiceDesk::SlaMilestone.create!(account: ticket.account, unit: ticket.unit, ticket: ticket, sla_snapshot: snapshot, kind: kind)
    end
    ticket.ticket_events.create!(account: ticket.account, unit: ticket.unit, actor_membership: actor,
                                 event_type: 'sla_snapshot_recorded', data: { 'snapshot_id' => snapshot.id, 'version' => snapshot.version,
                                                                              'payload_digest' => snapshot.payload_digest })
    snapshot
  end
end
