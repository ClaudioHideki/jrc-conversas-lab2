# frozen_string_literal: true

class ExtendJrcNicoHelpdeskDelivery < ActiveRecord::Migration[7.1]
  TABLE = :jrc_nico_helpdesk_delivery_receipts
  NEW_COLUMNS = %i[claim_token attempt_number payload_digest routing_digest dispatching_at sent_at evidence].freeze
  CHECKS = {
    nico_hd_receipt_state: "state IN ('pending', 'dispatching', 'sent', 'delivered', 'failed', 'blocked', 'unknown')",
    nico_hd_receipt_attempt: 'attempt_number >= 0',
    nico_hd_receipt_payload_digest: "payload_digest IS NULL OR payload_digest ~ '^[a-f0-9]{64}$'",
    nico_hd_receipt_routing_digest: "routing_digest IS NULL OR routing_digest ~ '^[a-f0-9]{64}$'",
    nico_hd_receipt_delivered: "(state = 'delivered') = (delivered_at IS NOT NULL)",
    nico_hd_receipt_sent: "(state <> 'sent' OR sent_at IS NOT NULL) AND (sent_at IS NULL OR state IN ('sent', 'delivered'))",
    nico_hd_receipt_claim: 'claim_token IS NULL OR attempt_number >= 1',
    nico_hd_receipt_dispatch: <<~SQL.squish
      state NOT IN ('dispatching', 'sent') OR
      (claim_token IS NOT NULL AND dispatching_at IS NOT NULL AND attempted_at IS NOT NULL
       AND payload_digest IS NOT NULL AND routing_digest IS NOT NULL AND attempt_number >= 1)
    SQL
  }.freeze

  def up
    add_column TABLE, :claim_token, :uuid
    add_column TABLE, :attempt_number, :integer, null: false, default: 0
    add_column TABLE, :payload_digest, :string, limit: 64
    add_column TABLE, :routing_digest, :string, limit: 64
    add_column TABLE, :dispatching_at, :datetime
    add_column TABLE, :sent_at, :datetime
    add_column TABLE, :evidence, :jsonb, null: false, default: {}
    CHECKS.each { |name, expression| add_check_constraint TABLE, expression, name: name }
  end

  def down
    connection.transaction do
      execute "LOCK TABLE #{connection.quote_table_name(TABLE)} IN ACCESS EXCLUSIVE MODE"
      raise ActiveRecord::IrreversibleMigration, 'R5 receipt extensions contain evidence; preserve the schema and rows' if extensions_used?

      CHECKS.each_key { |name| remove_check_constraint TABLE, name: name }
      NEW_COLUMNS.reverse_each { |column| remove_column TABLE, column }
    end
  end

  private

  def extensions_used?
    query = <<~SQL.squish
      SELECT EXISTS (
        SELECT 1 FROM #{connection.quote_table_name(TABLE)}
        WHERE state IN ('dispatching', 'sent') OR claim_token IS NOT NULL
          OR attempt_number <> 0 OR payload_digest IS NOT NULL OR routing_digest IS NOT NULL
          OR dispatching_at IS NOT NULL OR sent_at IS NOT NULL OR evidence <> '{}'::jsonb
      )
    SQL
    ActiveModel::Type::Boolean.new.cast(connection.select_value(query))
  end
end
