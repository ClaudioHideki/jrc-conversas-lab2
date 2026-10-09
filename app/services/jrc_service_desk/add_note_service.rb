# frozen_string_literal: true

class JrcServiceDesk::AddNoteService < JrcServiceDesk::BaseService
  FIELDS = %w[body visibility audience_team_id notification_channels notification_conversations previous_note_id publication_reason].freeze

  def call(ticket_id:, attributes:, idempotency_key:, files: [], preview_receipt: nil)
    draft = JrcServiceDesk::InteractionDraft.new(attributes: attributes, files: files, idempotency_key: idempotency_key,
                                                 preview_receipt: preview_receipt)
    result = JrcServiceDesk::TicketNote.no_touching do
      with_ticket(ticket_id, :add_note?) do |ticket|
        JrcServiceDesk::InteractionPublication.new(ticket: ticket, context: context, actor_membership: actor_membership).call(draft)
      end
    end
    JrcServiceDesk::NotificationEngine.new(result).call if result.notification_channels.any?
    result
  end
end
