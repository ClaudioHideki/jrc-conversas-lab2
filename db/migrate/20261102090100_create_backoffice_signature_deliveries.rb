class CreateBackofficeSignatureDeliveries < ActiveRecord::Migration[7.1]
  def up
    raise ActiveRecord::MigrationError, 'Consolidated LAB2 main history required; legacy A-G databases need explicit admission' unless table_exists?(:jrc_broker_webhook_obligations)
    raise ActiveRecord::MigrationError, 'Existing A-G signature history requires explicit admission, never automatic recreation' if table_exists?(:jrc_backoffice_signature_deliveries)

    add_index :jrc_backoffice_authority_proposals, %i[account_id contract_id backoffice_request_id signer_roster_id contract_version_id id],
              unique: true, name: 'bo_authority_exact_origin'
    create_deliveries
    create_events
    event_indexes
    add_fences
    execute File.read(Rails.root.join('db/functions/20261102090000_backoffice_signature_delivery_guards.sql'))
  end

  def down
    if select_value('SELECT id FROM jrc_backoffice_signature_deliveries LIMIT 1')
      raise ActiveRecord::IrreversibleMigration, 'Preserve admitted sends, original connections and signature history'
    end

    execute 'DROP TRIGGER jrc_contract_delivery_source_fence ON jrc_crm_contracts'
    execute 'DROP FUNCTION jrc_contract_delivery_source_fence()'
    drop_table :jrc_backoffice_signature_delivery_events
    drop_table :jrc_backoffice_signature_deliveries
    remove_index :jrc_backoffice_authority_proposals, name: 'bo_authority_exact_origin'
  end

  private

  def create_deliveries
    create_table :jrc_backoffice_signature_deliveries do |t|
      t.references :account, null: false, foreign_key: true
      t.references :contract, null: false, foreign_key: { to_table: :jrc_crm_contracts }
      t.references :backoffice_request, null: false, foreign_key: { to_table: :jrc_crm_backoffice_requests }
      t.references :contract_version, null: false, foreign_key: { to_table: :jrc_backoffice_contract_versions }
      t.references :signer_roster, null: false, foreign_key: { to_table: :jrc_backoffice_signer_rosters }
      t.references :authority_proposal, null: false, foreign_key: { to_table: :jrc_backoffice_authority_proposals }
      t.references :connection, null: false, foreign_key: { to_table: :jrc_backoffice_signature_connections }
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :idempotency_key, :input_digest, :source_digest, :transaction_id, null: false
      t.text :source_snapshot, null: false
      t.timestamps
    end
    add_index :jrc_backoffice_signature_deliveries, %i[account_id connection_id id], unique: true, name: 'bo_delivery_tenant_connection'
    add_index :jrc_backoffice_signature_deliveries, :contract_version_id, unique: true, name: 'bo_delivery_one_envelope_per_version'
    add_index :jrc_backoffice_signature_deliveries, :transaction_id, unique: true, name: 'bo_delivery_transaction'
    add_index :jrc_backoffice_signature_deliveries, %i[account_id created_by_id idempotency_key], unique: true, name: 'bo_delivery_intent'
  end

  def create_events
    create_table :jrc_backoffice_signature_delivery_events do |t|
      t.references :account, null: false, foreign_key: true
      t.references :delivery, null: false, foreign_key: { to_table: :jrc_backoffice_signature_deliveries }
      t.bigint :connection_id, null: false
      t.string :kind, :event_key, null: false
      t.string :external_id
      t.text :source_snapshot, null: false
      t.timestamps
    end
  end

  def event_indexes
    add_index :jrc_backoffice_signature_delivery_events, %i[delivery_id event_key], unique: true, name: 'bo_delivery_event_intent'
    add_index :jrc_backoffice_signature_delivery_events, :delivery_id, unique: true, where: "kind = 'dispatch_started'",
                                                                       name: 'bo_delivery_dispatch_once'
    add_index :jrc_backoffice_signature_delivery_events, :delivery_id, unique: true, where: 'external_id IS NOT NULL',
                                                                       name: 'bo_delivery_one_external_binding'
    add_index :jrc_backoffice_signature_delivery_events, %i[connection_id external_id], unique: true, where: 'external_id IS NOT NULL',
                                                                                        name: 'bo_delivery_external_origin'
    add_check_constraint :jrc_backoffice_signature_delivery_events,
                         "(kind = 'send_confirmed') = (external_id IS NOT NULL)", name: 'bo_delivery_confirmed_requires_envelope'
    add_check_constraint :jrc_backoffice_signature_delivery_events,
                         "kind IN ('prepared', 'dispatch_started', 'send_confirmed', 'send_uncertain', 'send_rejected', 'sender_blocked', " \
                         "'canceled_before_send', 'completion_reported', 'envelope_canceled', 'envelope_declined')", name: 'bo_delivery_event_kind'
  end

  def add_fences
    add_foreign_key :jrc_backoffice_signature_deliveries, :jrc_backoffice_authority_proposals,
                    column: %i[account_id contract_id backoffice_request_id signer_roster_id contract_version_id authority_proposal_id],
                    primary_key: %i[account_id contract_id backoffice_request_id signer_roster_id contract_version_id id],
                    name: 'bo_delivery_exact_authority'
    add_foreign_key :jrc_backoffice_signature_deliveries, :jrc_backoffice_signature_connections,
                    column: %i[account_id connection_id], primary_key: %i[account_id id], name: 'bo_delivery_tenant_connection_fk'
    add_foreign_key :jrc_backoffice_signature_delivery_events, :jrc_backoffice_signature_deliveries,
                    column: %i[account_id connection_id delivery_id], primary_key: %i[account_id connection_id id],
                    name: 'bo_delivery_event_exact_origin'
    %w[signature_deliveries signature_delivery_events].each do |suffix|
      execute <<~SQL.squish
        CREATE TRIGGER jrc_#{suffix}_pin BEFORE UPDATE OR DELETE ON jrc_backoffice_#{suffix}
        FOR EACH ROW EXECUTE FUNCTION jrc_contract_version_pin();
      SQL
    end
  end
end
