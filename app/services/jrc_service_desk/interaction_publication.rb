# frozen_string_literal: true

class JrcServiceDesk::InteractionPublication
  def initialize(ticket:, context:, actor_membership:)
    @ticket = ticket
    @context = context
    @actor = actor_membership
  end

  def call(draft)
    JrcServiceDesk::InteractionVisibility.authorize_publication!(@context, @ticket, **draft.audience)
    previous = previous(draft)
    existing = existing(draft)
    return existing if existing

    note = build_note(draft, previous)
    preview_digest = preview_digest(draft)
    Pundit.authorize(@context.to_h, note, :create?)
    # The immutable interaction retains its creation timestamp after attachment insertion.
    note.files.attach(draft.uploads.map { |file| file.except(:sha256) }) if draft.uploads.any?
    note.save!
    append_event(note, previous, preview_digest)
    note
  end

  private

  def previous(draft)
    return unless draft.values['previous_note_id']

    note = @ticket.ticket_notes.find(JrcServiceDesk::Input.id(draft.values['previous_note_id']))
    Pundit.authorize(@context.to_h, note, :show?)
    reason = draft.values['publication_reason']
    raise ArgumentError, 'Explicit publication reason required' unless reason.is_a?(String) && reason.strip.present?

    note
  end

  def existing(draft)
    row = JrcServiceDesk::TicketNote.find_by(account: @context.account, unit: @ticket.unit, ticket: @ticket,
                                             author_membership: @actor, idempotency_key: draft.key)
    raise JrcServiceDesk::IdempotencyConflict, 'Idempotency key belongs to a different note' if row && row.request_fingerprint != draft.fingerprint

    row
  end

  def preview_digest(draft)
    return unless draft.preview_receipt || JrcServiceDesk::InteractionVisibility::PUBLIC.include?(draft.audience[:visibility])

    JrcServiceDesk::InteractionPreview.new(ticket: @ticket, context: @context).verify!(
      draft.preview_receipt, attributes: draft.values, file_fingerprints: draft.file_fingerprints
    )
  end

  def build_note(draft, previous)
    JrcServiceDesk::TicketNote.new(account: @context.account, unit: @ticket.unit, ticket: @ticket,
                                   author_membership: @actor, body: draft.body, **draft.audience, previous_note: previous,
                                   publication_reason: draft.values['publication_reason'], notification_conversations: draft.destinations,
                                   idempotency_key: draft.key, request_fingerprint: draft.fingerprint)
  end

  def append_event(note, previous, preview_digest)
    JrcServiceDesk::TicketEvent.create!(account: @context.account, unit: @ticket.unit, ticket: @ticket, actor_membership: @actor,
                                        event_type: previous ? 'interaction_republished' : 'note_added', visibility: note.visibility,
                                        audience_team_id: note.audience_team_id,
                                        data: { 'note_id' => note.id, 'previous_note_id' => previous&.id,
                                                'notification_state' => note.notification_state, 'preview_digest' => preview_digest })
  end
end
