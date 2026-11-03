class EnforceJrcMigrationMediaIdentity < ActiveRecord::Migration[7.1]
  def up
    remove_check_constraint :jrc_migration_media_objects, name: 'jrc_migration_media_destination_identity'
    add_check_constraint :jrc_migration_media_objects,
                         "(storage_identity IS NULL AND status = 'kept') OR " \
                         "(storage_identity IS NOT NULL AND storage_identity ~ '^[a-f0-9]{64}$')",
                         name: 'jrc_migration_media_destination_identity'
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Media ownership must not accept SQL UNKNOWN as proof'
  end
end
