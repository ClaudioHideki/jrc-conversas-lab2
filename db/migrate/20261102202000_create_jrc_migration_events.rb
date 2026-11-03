class CreateJrcMigrationEvents < ActiveRecord::Migration[7.1]
  IMMUTABILITY_SQL = <<~SQL.squish.freeze
    CREATE FUNCTION jrc_migration_event_guard() RETURNS trigger
    LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
    BEGIN
      IF TG_OP = 'DELETE' AND pg_trigger_depth() > 1 AND (
        NOT EXISTS (SELECT 1 FROM public.accounts WHERE id = OLD.account_id) OR
        NOT EXISTS (SELECT 1 FROM public.jrc_migration_batches WHERE id = OLD.batch_id)
      ) THEN RETURN OLD;
      ELSIF TG_OP = 'UPDATE' AND pg_trigger_depth() > 1 AND OLD.user_id IS NOT NULL AND NEW.user_id IS NULL AND
        (to_jsonb(NEW) - 'user_id') IS NOT DISTINCT FROM (to_jsonb(OLD) - 'user_id') AND
        NOT EXISTS (SELECT 1 FROM public.users WHERE id = OLD.user_id)
      THEN RETURN NEW;
      END IF;
      RAISE EXCEPTION 'Migration history is append-only' USING ERRCODE = '23514';
    END;
    $$;
    CREATE TRIGGER jrc_migration_event_rows BEFORE UPDATE OR DELETE ON jrc_migration_events
      FOR EACH ROW EXECUTE FUNCTION jrc_migration_event_guard();
    CREATE TRIGGER jrc_migration_event_truncate BEFORE TRUNCATE ON jrc_migration_events
      FOR EACH STATEMENT EXECUTE FUNCTION jrc_migration_event_guard();
  SQL
  private_constant :IMMUTABILITY_SQL

  def up
    create_table :jrc_migration_events do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :batch_id, null: false
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :action, null: false
      t.jsonb :metadata, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.datetime :created_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
    end
    add_index :jrc_migration_events, [:account_id, :batch_id, :id], name: 'jrc_migration_event_history'
    add_foreign_key :jrc_migration_events, :jrc_migration_batches, column: [:account_id, :batch_id],
                                                                   primary_key: [:account_id, :id], on_delete: :cascade
    execute IMMUTABILITY_SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Migration audit history must be preserved'
  end
end
