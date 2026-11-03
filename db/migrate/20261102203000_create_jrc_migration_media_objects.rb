class CreateJrcMigrationMediaObjects < ActiveRecord::Migration[7.1]
  def up
    add_index :jrc_migration_items, [:account_id, :batch_id, :id], unique: true, name: 'jrc_migration_item_tenant_batch'
    create_table :jrc_migration_media_objects do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :batch_id, null: false
      t.bigint :item_id, null: false
      t.integer :generation, null: false
      t.string :service_name, null: false
      t.string :storage_key, null: false
      t.string :source_sha256, null: false
      t.bigint :byte_size, null: false
      t.string :status, null: false, default: 'planned'
      t.references :blob, foreign_key: { to_table: :active_storage_blobs, on_delete: :nullify }
      t.uuid :claim_token
      t.datetime :claimed_at
      t.datetime :checked_at
      t.string :error_code
      t.timestamps
    end
    add_foreign_key :jrc_migration_media_objects, :jrc_migration_items, column: [:account_id, :batch_id, :item_id],
                                                                       primary_key: [:account_id, :batch_id, :id], on_delete: :cascade
    add_index :jrc_migration_media_objects, [:item_id, :generation], unique: true, name: 'jrc_migration_media_generation'
    add_index :jrc_migration_media_objects, [:service_name, :storage_key], unique: true, name: 'jrc_migration_media_storage_identity'
    add_check_constraint :jrc_migration_media_objects, "storage_key ~ '^[a-z0-9]{28}$' AND source_sha256 ~ '^[a-f0-9]{64}$'",
                         name: 'jrc_migration_media_identity_format'
    add_check_constraint :jrc_migration_media_objects, 'generation > 0 AND byte_size > 0 AND byte_size <= 1048576',
                         name: 'jrc_migration_media_payload_bound'
    add_check_constraint :jrc_migration_media_objects, "status IN ('planned','attached','recovering','cleanup_required','cleaned','kept')",
                         name: 'jrc_migration_media_status'
    execute <<~SQL
      CREATE FUNCTION jrc_migration_media_owner_guard() RETURNS trigger
      LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
      BEGIN
        IF TG_OP = 'DELETE' AND pg_trigger_depth() > 1 AND
          NOT EXISTS (SELECT 1 FROM public.jrc_migration_items WHERE id = OLD.item_id AND account_id = OLD.account_id)
        THEN RETURN OLD;
        ELSIF TG_OP = 'UPDATE' AND
          (to_jsonb(NEW) - ARRAY['status','blob_id','claim_token','claimed_at','checked_at','error_code','updated_at']) IS NOT DISTINCT FROM
          (to_jsonb(OLD) - ARRAY['status','blob_id','claim_token','claimed_at','checked_at','error_code','updated_at'])
        THEN RETURN NEW;
        END IF;
        RAISE EXCEPTION 'Migration media ownership is immutable' USING ERRCODE = '23514';
      END;
      $$;
      CREATE TRIGGER jrc_migration_media_owner_rows BEFORE UPDATE OR DELETE ON jrc_migration_media_objects
        FOR EACH ROW EXECUTE FUNCTION jrc_migration_media_owner_guard();
      CREATE TRIGGER jrc_migration_media_owner_truncate BEFORE TRUNCATE ON jrc_migration_media_objects
        FOR EACH STATEMENT EXECUTE FUNCTION jrc_migration_media_owner_guard();
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Durable storage ownership must survive until its physical objects are reconciled'
  end
end
