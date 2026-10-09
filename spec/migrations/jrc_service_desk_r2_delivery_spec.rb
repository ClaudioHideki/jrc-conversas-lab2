# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk do
  include_context 'JRC Service Desk domain'

  def raw_insert(model, fields)
    connection = model.connection
    columns = fields.keys.map { |key| connection.quote_column_name(key) }.join(', ')
    placeholders = fields.keys.each_index.map { |index| "$#{index + 1}" }.join(', ')
    bindings = fields.map do |key, value|
      ActiveRecord::Relation::QueryAttribute.new(key.to_s, value, model.type_for_attribute(key.to_s))
    end
    sql = "INSERT INTO #{connection.quote_table_name(model.table_name)} (#{columns}) VALUES (#{placeholders}) " \
          "RETURNING #{connection.quote_column_name(model.primary_key)}"
    model.transaction(requires_new: true) { connection.exec_query(sql, 'Database constraint fixture', bindings) }
  end

  it 'preserves the required explicit OLA pause policy without a database fallback' do
    column = JrcServiceDesk::OlaClock.columns_hash.fetch('pause_waiting')
    expect(column.null).to be(false)
    expect(column.default).to be_nil
    queue = create(:jrc_sd_queue, unit: sd_unit)
    ticket = sd_ticket(queue: queue)
    fields = { account_id: sd_account.id, unit_id: sd_unit.id, ticket_id: ticket.id, queue_id: queue.id,
               budget_seconds: 300, time_basis: 'calendar', policy_revision: 'controlled-test', state: 'stopped',
               started_at: Time.current, anchor_at: Time.current, due_at: 5.minutes.from_now, elapsed_seconds: 0,
               created_at: Time.current, updated_at: Time.current }
    expect { raw_insert(JrcServiceDesk::OlaClock, fields) }.to raise_error(ActiveRecord::NotNullViolation)
    [false, true].each do |value|
      result = raw_insert(JrcServiceDesk::OlaClock, fields.merge(pause_waiting: value))
      expect(JrcServiceDesk::OlaClock.find(result.rows.first.first).pause_waiting).to eq(value)
    end
  end

  it 'enforces one scoped immutable origin and positive attempts in the database' do
    ticket = sd_ticket
    note = create(:jrc_sd_note, ticket: ticket)
    event = create(:jrc_sd_event, ticket: ticket)
    fields = { account_id: sd_account.id, unit_id: sd_unit.id, ticket_id: ticket.id, execution_membership_id: sd_membership.id,
               channel: 'email', state: 'blocked', reason: 'policy_disabled', created_at: Time.current, updated_at: Time.current }
    invalid = [fields, fields.merge(ticket_note_id: note.id, ticket_event_id: event.id),
               fields.merge(ticket_note_id: note.id, attempt_number: 0)]
    invalid.each do |values|
      expect { raw_insert(JrcServiceDesk::NotificationDelivery, values) }
        .to raise_error(ActiveRecord::StatementInvalid, /jrc_sd_delivery_(one_origin|attempt_positive)/)
    end
    result = raw_insert(JrcServiceDesk::NotificationDelivery, fields.merge(ticket_event_id: event.id))
    expect(JrcServiceDesk::NotificationDelivery.find(result.rows.first.first).attempt_number).to eq(1)
  end

  it 'rejects event and original-attempt references from a different ticket in SQL' do
    ticket = sd_ticket
    other = sd_ticket
    event = create(:jrc_sd_event, ticket: other)
    note = create(:jrc_sd_note, ticket: ticket)
    fields = { account_id: sd_account.id, unit_id: sd_unit.id, ticket_id: ticket.id, execution_membership_id: sd_membership.id,
               channel: 'email', state: 'blocked', reason: 'policy_disabled', created_at: Time.current, updated_at: Time.current }
    expect { raw_insert(JrcServiceDesk::NotificationDelivery, fields.merge(ticket_event_id: event.id)) }
      .to raise_error(ActiveRecord::InvalidForeignKey, /jrc_sd_delivery_event_scope_fk/)
    original = JrcServiceDesk::NotificationDelivery.create!(
      account: sd_account, unit: sd_unit, ticket: other, ticket_event: event,
      execution_membership: sd_membership, channel: 'email', state: 'blocked'
    )
    expect { raw_insert(JrcServiceDesk::NotificationDelivery, fields.merge(ticket_note_id: note.id, original_delivery_id: original.id)) }
      .to raise_error(ActiveRecord::InvalidForeignKey, /jrc_sd_delivery_original_scope_fk/)
  end
end
