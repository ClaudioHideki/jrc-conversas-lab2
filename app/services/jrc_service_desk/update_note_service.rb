# frozen_string_literal: true

# Correct an internal note by publishing an immutable replacement. External
# messages keep the existing explicit preview/publication workflow.
class JrcServiceDesk::UpdateNoteService < JrcServiceDesk::BaseService
  def call(ticket_id:, note_id:, attributes:, reason:, idempotency_key:)
    values = JrcServiceDesk::Input.attributes(attributes, %w[body])
    reason = JrcServiceDesk::RecordWithdrawal.reason(reason)
    key = JrcServiceDesk::Input.request_key(idempotency_key)
    identifier = JrcServiceDesk::Input.id(note_id)
    fingerprint = JrcServiceDesk::CanonicalJson.digest(values.merge('previous_note_id' => identifier, 'publication_reason' => reason))
    with_ticket(ticket_id, :add_note?) do |ticket|
      previous = ticket.ticket_notes.find(identifier)
      existing = ticket.ticket_notes.find_by(author_membership_id: actor_membership.id, idempotency_key: key)
      if existing
        authorize!(existing, :show?)
        raise JrcServiceDesk::IdempotencyConflict unless existing.request_fingerprint == fingerprint

        next existing
      end
      authorize!(previous, :update?)
      note = ticket.ticket_notes.new(
        account: context.account, unit: ticket.unit, author_membership: actor_membership,
        body: text(values.fetch('body')), visibility: previous.visibility, audience_team_id: previous.audience_team_id,
        previous_note: previous, publication_reason: reason, notification_channels: [], notification_state: 'not_requested',
        idempotency_key: key, request_fingerprint: fingerprint
      )
      authorize!(note, :create?)
      files = JrcServiceDesk::RecordWithdrawal.attachments(previous)
      note.files.attach(files.map(&:blob)) if files.any?
      note.save!
      { 'interaction_republished' => { 'note_id' => note.id, 'previous_note_id' => previous.id, 'notification_state' => 'not_requested' },
        'note_withdrawn' => { 'note_id' => previous.id, 'replacement_note_id' => note.id, 'reason' => reason } }.each do |type, data|
        JrcServiceDesk::TicketEvent.create!(
          account: context.account, unit: ticket.unit, ticket: ticket, actor_membership: actor_membership,
          event_type: type, visibility: note.visibility, audience_team_id: note.audience_team_id, data: data
        )
      end
      note
    end
  end
end
