class HardenJrcMigrationMediaProtocol < ActiveRecord::Migration[7.1]
  OWNER_GUARD_SQL = <<~SQL.squish.freeze
    CREATE OR REPLACE FUNCTION jrc_migration_media_owner_guard() RETURNS trigger
    LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
    BEGIN
      IF TG_OP = 'DELETE' AND pg_trigger_depth() > 1 AND
        NOT EXISTS (SELECT 1 FROM public.jrc_migration_items WHERE id = OLD.item_id AND account_id = OLD.account_id)
      THEN RETURN OLD;
      ELSIF TG_OP = 'UPDATE' AND
        (to_jsonb(NEW) - ARRAY['status','blob_id','claim_token','claimed_at','checked_at','error_code','updated_at',
                             'absence_verified_at','scan_generation','scan_token','scan_started_at']) IS NOT DISTINCT FROM
        (to_jsonb(OLD) - ARRAY['status','blob_id','claim_token','claimed_at','checked_at','error_code','updated_at',
                             'absence_verified_at','scan_generation','scan_token','scan_started_at']) AND
        (NEW.absence_verified_at IS NOT DISTINCT FROM OLD.absence_verified_at OR
          (OLD.absence_verified_at IS NULL AND NEW.absence_verified_at IS NOT NULL AND OLD.status = 'verifying' AND NEW.status = 'planned')) AND
        NEW.scan_generation >= OLD.scan_generation
      THEN RETURN NEW;
      END IF;
      RAISE EXCEPTION 'Migration media ownership is immutable' USING ERRCODE = '23514';
    END;
    $$;
  SQL
  private_constant :OWNER_GUARD_SQL

  def up
    add_reservation_fields
    preserve_legacy_reservations
    enforce_reservation_proof
    execute OWNER_GUARD_SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Storage ownership and scan fencing evidence must be retained'
  end

  private

  def add_reservation_fields
    add_column :jrc_migration_media_objects, :storage_identity, :string
    add_column :jrc_migration_media_objects, :absence_verified_at, :datetime
    add_column :jrc_migration_media_objects, :scan_generation, :integer, null: false, default: 0
    add_column :jrc_migration_media_objects, :scan_token, :uuid
    add_column :jrc_migration_media_objects, :scan_started_at, :datetime
  end

  def preserve_legacy_reservations
    # Older reservations have no physical absence/destination proof. Keep bytes.
    execute <<~SQL.squish
      UPDATE jrc_migration_media_objects
      SET status = 'kept', error_code = 'MEDIA_PROVENANCE_REQUIRED', claim_token = NULL, claimed_at = NULL;
    SQL
  end

  def enforce_reservation_proof
    change_column_default :jrc_migration_media_objects, :status, from: 'planned', to: 'reserved'
    remove_check_constraint :jrc_migration_media_objects, name: 'jrc_migration_media_status'
    add_check_constraint :jrc_migration_media_objects,
                         "status IN ('reserved','verifying','verification_required','planned','attached','recovering'," \
                         "'cleanup_required','cleaned','kept')",
                         name: 'jrc_migration_media_status'
    add_check_constraint :jrc_migration_media_objects,
                         "(storage_identity IS NULL AND status = 'kept') OR storage_identity ~ '^[a-f0-9]{64}$'",
                         name: 'jrc_migration_media_destination_identity'
    add_check_constraint :jrc_migration_media_objects,
                         "status NOT IN ('planned','attached','recovering','cleanup_required','cleaned') OR absence_verified_at IS NOT NULL",
                         name: 'jrc_migration_media_absence_before_write'
    add_check_constraint :jrc_migration_media_objects, 'scan_generation >= 0', name: 'jrc_migration_media_scan_generation'
  end
end
