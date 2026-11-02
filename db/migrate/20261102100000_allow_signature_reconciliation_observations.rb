# Reconciliation observations are append-only facts, never state transitions.
class AllowSignatureReconciliationObservations < ActiveRecord::Migration[7.1]
  ORIGINAL = %w[prepared dispatch_started send_confirmed send_uncertain send_rejected sender_blocked canceled_before_send
                completion_reported envelope_canceled envelope_declined].freeze
  OBSERVATIONS = %w[reconciliation_started reconciliation_finished].freeze

  def up
    replace_constraint(ORIGINAL + OBSERVATIONS)
  end

  def down
    found = select_value(<<~SQL.squish)
      SELECT id FROM jrc_backoffice_signature_delivery_events
      WHERE kind IN ('reconciliation_started', 'reconciliation_finished') LIMIT 1
    SQL
    raise ActiveRecord::IrreversibleMigration, 'Preserve signature reconciliation history' if found

    replace_constraint(ORIGINAL)
  end

  private

  def replace_constraint(kinds)
    remove_check_constraint :jrc_backoffice_signature_delivery_events, name: 'bo_delivery_event_kind'
    values = kinds.map { |kind| connection.quote(kind) }.join(', ')
    add_check_constraint :jrc_backoffice_signature_delivery_events, "kind IN (#{values})", name: 'bo_delivery_event_kind'
  end
end
