class CreateJrcBrokerConnectionEvents < ActiveRecord::Migration[7.1]
  IMMUTABILITY_SQL = <<~SQL.squish.freeze
    CREATE FUNCTION jrc_connection_event_immutable_guard() RETURNS trigger
    LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
    BEGIN
      IF TG_OP = 'DELETE' AND pg_trigger_depth() > 1 AND (
        NOT EXISTS (SELECT 1 FROM public.accounts WHERE id = OLD.account_id) OR
        NOT EXISTS (SELECT 1 FROM public.inboxes WHERE id = OLD.inbox_id)
      ) THEN RETURN OLD;
      ELSIF TG_OP = 'UPDATE' AND pg_trigger_depth() > 1 AND OLD.user_id IS NOT NULL AND NEW.user_id IS NULL AND
        (to_jsonb(NEW) - 'user_id') IS NOT DISTINCT FROM (to_jsonb(OLD) - 'user_id') AND
        NOT EXISTS (SELECT 1 FROM public.users WHERE id = OLD.user_id)
      THEN RETURN NEW;
      END IF;
      RAISE EXCEPTION 'Connection history is append-only' USING ERRCODE = '23514';
    END;
    $$;
    CREATE TRIGGER jrc_connection_event_immutable_rows BEFORE UPDATE OR DELETE ON jrc_broker_connection_events
      FOR EACH ROW EXECUTE FUNCTION jrc_connection_event_immutable_guard();
    CREATE TRIGGER jrc_connection_event_immutable_truncate BEFORE TRUNCATE ON jrc_broker_connection_events
      FOR EACH STATEMENT EXECUTE FUNCTION jrc_connection_event_immutable_guard();
  SQL
  private_constant :IMMUTABILITY_SQL

  def up
    create_events_table
    add_index :jrc_broker_connection_events, [:account_id, :inbox_id, :id], name: 'jrc_connection_events_history'
    add_index :jrc_broker_connection_events, [:account_id, :inbox_id, :event_key], unique: true, name: 'jrc_connection_events_dedupe'
    add_column :jrc_broker_inbox_bindings, :connection_state, :jsonb, null: false, default: {}
    execute IMMUTABILITY_SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Connection audit history must be preserved'
  end

  private

  def create_events_table
    create_table :jrc_broker_connection_events do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :event_type, null: false
      t.string :event_key
      t.string :status_before
      t.string :status_after
      t.string :correlation_id
      t.datetime :occurred_at, null: false
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
    end
  end
end
