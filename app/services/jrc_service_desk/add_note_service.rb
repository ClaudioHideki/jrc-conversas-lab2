# frozen_string_literal: true

class JrcServiceDesk::AddNoteService < JrcServiceDesk::BaseService
  def call(ticket_id:, attributes:, idempotency_key:)
    values = JrcServiceDesk::Input.attributes(attributes, %w[body])
    body = text(values['body'])
    key = JrcServiceDesk::Input.request_key(idempotency_key)
    fingerprint = JrcServiceDesk::CanonicalJson.digest('body' => body)

    with_ticket(ticket_id, :add_note?) do |ticket|
      existing = JrcServiceDesk::TicketNote.find_by(account_id: context.account.id, unit_id: ticket.unit_id, ticket_id: ticket.id,
                                                     author_membership_id: actor_membership.id, idempotency_key: key)
      if existing
        raise JrcServiceDesk::IdempotencyConflict, 'Idempotency key belongs to a different note' unless existing.request_fingerprint == fingerprint

        next existing
      end
      note = JrcServiceDesk::TicketNote.new(account: context.account, unit: ticket.unit, ticket: ticket,
                                              author_membership: actor_membership, body: body, visibility: 'internal',
                                              idempotency_key: key, request_fingerprint: fingerprint)
      authorize!(note, :create?)
      note.save!
      append_event!(ticket, 'note_added', 'note_id' => note.id)
      note
    end
  end
end
