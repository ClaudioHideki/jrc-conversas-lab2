# frozen_string_literal: true

# Removal is an immutable audit event. Original records, provider receipts and
# foreign keys remain intact; operational projections exclude withdrawn items.
module JrcServiceDesk::RecordWithdrawal
  EVENTS = { ticket: 'ticket_deleted', task: 'task_deleted', note: 'note_withdrawn', attachment: 'attachment_withdrawn' }.freeze

  def self.excluding(relation, kind)
    table = relation.klass.table_name
    event = EVENTS.fetch(kind)
    match = kind == :ticket ? "withdrawals.ticket_id = #{table}.id" : "withdrawals.data->>'#{kind}_id' = #{table}.id::text"
    relation.where(<<~SQL.squish, event)
      NOT EXISTS (
        SELECT 1 FROM jrc_service_desk_ticket_events withdrawals
        WHERE withdrawals.account_id = #{table}.account_id
          AND withdrawals.unit_id = #{table}.unit_id
          AND withdrawals.ticket_id = #{kind == :ticket ? "#{table}.id" : "#{table}.ticket_id"}
          AND withdrawals.event_type = ? AND #{match}
      )
    SQL
  end

  def self.withdrawn?(record, kind)
    events = JrcServiceDesk::TicketEvent.where(account_id: record.account_id, unit_id: record.unit_id,
                                               ticket_id: kind == :ticket ? record.id : record.ticket_id, event_type: EVENTS.fetch(kind))
    events = events.where("data->>? = ?", "#{kind}_id", record.id.to_s) unless kind == :ticket
    events.exists?
  end

  def self.attachments(note)
    events = JrcServiceDesk::TicketEvent.where(account_id: note.account_id, unit_id: note.unit_id, ticket_id: note.ticket_id,
                                               event_type: EVENTS.fetch(:attachment)).where("data->>'note_id' = ?", note.id.to_s)
    removed = events.pluck(Arel.sql("data->>'attachment_id'"))
    note.files.reject { |file| removed.include?(file.id.to_s) }
  end

  def self.with_attachments(relation)
    relation.where(<<~SQL.squish)
      EXISTS (
        SELECT 1 FROM active_storage_attachments attachments
        WHERE attachments.record_type = 'JrcServiceDesk::TicketNote'
          AND attachments.record_id = jrc_service_desk_ticket_notes.id
          AND NOT EXISTS (
            SELECT 1 FROM jrc_service_desk_ticket_events withdrawals
            WHERE withdrawals.account_id = jrc_service_desk_ticket_notes.account_id
              AND withdrawals.unit_id = jrc_service_desk_ticket_notes.unit_id
              AND withdrawals.ticket_id = jrc_service_desk_ticket_notes.ticket_id
              AND withdrawals.event_type = 'attachment_withdrawn'
              AND withdrawals.data->>'attachment_id' = attachments.id::text
          )
      )
    SQL
  end

  def self.reason(value)
    raise ArgumentError, 'Informe um motivo de 3 a 1000 caracteres' unless value.is_a?(String) && value.strip.length.between?(3, 1000)

    value.strip
  end
end
