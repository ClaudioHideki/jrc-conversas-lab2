# frozen_string_literal: true

class JrcServiceDesk::WithdrawNoteService < JrcServiceDesk::BaseService
  def call(ticket_id:, note_id:, reason:, attachment_id: nil)
    reason = JrcServiceDesk::RecordWithdrawal.reason(reason)
    with_ticket(ticket_id, :show?) do |ticket|
      note = ticket.ticket_notes.find(JrcServiceDesk::Input.id(note_id))
      authorize!(note, :destroy?)
      data = { 'note_id' => note.id, 'reason' => reason }
      if attachment_id
        identifier = JrcServiceDesk::Input.id(attachment_id)
        file = JrcServiceDesk::RecordWithdrawal.attachments(note).find { |attachment| attachment.id == identifier }
        raise ActiveRecord::RecordNotFound unless file

        data['attachment_id'] = file.id
        data['filename'] = file.filename.to_s
      end
      JrcServiceDesk::TicketEvent.create!(
        account: context.account, unit: ticket.unit, ticket: ticket, actor_membership: actor_membership,
        event_type: attachment_id ? 'attachment_withdrawn' : 'note_withdrawn', visibility: note.visibility,
        audience_team_id: note.audience_team_id, data: data
      )
      note
    end
  end
end
