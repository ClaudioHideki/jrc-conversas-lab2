class CreatePortfolioHistoryReceipts < ActiveRecord::Migration[7.1]
  def up
    create_table :jrc_relationship_portfolio_history_receipts do |table|
      table.references :account, null: false, type: :integer, foreign_key: { on_delete: :cascade }
      table.bigint :portfolio_group_id, null: false
      table.bigint :audit_event_id, null: false
      table.jsonb :snapshot, null: false
      table.string :digest, null: false, limit: 64
      table.datetime :created_at, null: false
    end
    add_index :jrc_relationship_portfolio_history_receipts, :audit_event_id, unique: true, name: 'idx_rel_portfolio_history_event'
    add_index :jrc_relationship_portfolio_history_receipts, [:account_id, :portfolio_group_id, :id], name: 'idx_rel_portfolio_history_scope'
    add_foreign_key :jrc_relationship_portfolio_history_receipts, :jrc_relationship_portfolio_groups,
                    column: :portfolio_group_id, on_delete: :restrict
    add_foreign_key :jrc_relationship_portfolio_history_receipts, :jrc_crm_audit_events,
                    column: :audit_event_id, on_delete: :cascade
    add_check_constraint :jrc_relationship_portfolio_history_receipts,
                         "jsonb_typeof(snapshot) = 'object' AND digest ~ '^[a-f0-9]{64}$'", name: 'rel_portfolio_history_shape'
    execute <<~SQL
      CREATE FUNCTION jrc_rel_history_receipt_guard() RETURNS trigger AS $$
      DECLARE native_group_account integer; native_event jrc_crm_audit_events%ROWTYPE;
      BEGIN
        IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id) THEN
          RETURN OLD; -- Keep the existing explicit whole-account lifecycle.
        END IF;
        IF TG_OP <> 'INSERT' THEN
          RAISE EXCEPTION 'Portfolio history receipts are immutable' USING ERRCODE = '23514';
        END IF;
        SELECT account_id INTO native_group_account FROM jrc_relationship_portfolio_groups WHERE id = NEW.portfolio_group_id;
        SELECT * INTO native_event FROM jrc_crm_audit_events WHERE id = NEW.audit_event_id;
        IF native_group_account IS DISTINCT FROM NEW.account_id OR native_event.account_id IS DISTINCT FROM NEW.account_id
           OR native_event.event_type IS DISTINCT FROM 'relationship_updated' THEN
          RAISE EXCEPTION 'Portfolio history scope mismatch' USING ERRCODE = '23514';
        END IF;
        IF NOT ((native_event.resource_type = 'JrcRelationship::PortfolioGroup' AND native_event.resource_id = NEW.portfolio_group_id)
           OR (native_event.resource_type = 'JrcRelationship::Configuration' AND EXISTS (
             SELECT 1 FROM jrc_relationship_configurations WHERE id = native_event.resource_id AND account_id = NEW.account_id
             AND scope_key = 'portfolio:' || NEW.portfolio_group_id::text))) THEN
          RAISE EXCEPTION 'Portfolio history origin mismatch' USING ERRCODE = '23514';
        END IF;
        IF NEW.snapshot ->> 'account_id' IS DISTINCT FROM NEW.account_id::text
           OR NEW.snapshot ->> 'group_id' IS DISTINCT FROM NEW.portfolio_group_id::text
           OR NEW.snapshot ->> 'version' IS DISTINCT FROM '1'
           OR jsonb_typeof(NEW.snapshot -> 'boundaries') IS DISTINCT FROM 'array'
           OR jsonb_typeof(NEW.snapshot -> 'origins') IS DISTINCT FROM 'array'
           OR NEW.snapshot ->> 'resolved' IS DISTINCT FROM 'true' THEN
          RAISE EXCEPTION 'Portfolio history snapshot mismatch' USING ERRCODE = '23514';
        END IF;
        RETURN NEW;
      END; $$ LANGUAGE plpgsql;
      CREATE TRIGGER rel_history_receipt_guard BEFORE INSERT OR UPDATE OR DELETE
        ON jrc_relationship_portfolio_history_receipts FOR EACH ROW EXECUTE FUNCTION jrc_rel_history_receipt_guard();
      CREATE FUNCTION jrc_rel_history_source_guard() RETURNS trigger AS $$
      BEGIN
        IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id) THEN RETURN OLD; END IF;
        IF EXISTS (SELECT 1 FROM jrc_relationship_portfolio_history_receipts WHERE audit_event_id = OLD.id) THEN
          RAISE EXCEPTION 'Captured portfolio audit events are immutable' USING ERRCODE = '23514';
        END IF;
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
        RETURN NEW;
      END; $$ LANGUAGE plpgsql;
      CREATE TRIGGER rel_history_source_guard BEFORE UPDATE OR DELETE ON jrc_crm_audit_events
        FOR EACH ROW EXECUTE FUNCTION jrc_rel_history_source_guard();
    SQL
  end

  def down
    execute 'DROP TRIGGER IF EXISTS rel_history_source_guard ON jrc_crm_audit_events'
    execute 'DROP FUNCTION IF EXISTS jrc_rel_history_source_guard()'
    drop_table :jrc_relationship_portfolio_history_receipts
    execute 'DROP FUNCTION IF EXISTS jrc_rel_history_receipt_guard()'
  end
end
