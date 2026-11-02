class PinSignatureProviderConnections < ActiveRecord::Migration[7.1]
  def up
    add_column :jrc_backoffice_signature_integrations, :provider, :string, null: false, default: 'docusign'
    create_connections
    index_connections
    copy_current_configuration
    link_existing_notifications
    pin_configuration
  end

  def down
    remove_foreign_key :jrc_backoffice_signature_notifications, name: 'bo_signature_notification_connection_tenant'
    remove_reference :jrc_backoffice_signature_notifications, :connection, foreign_key: { to_table: :jrc_backoffice_signature_connections }
    drop_table :jrc_backoffice_signature_connections
    execute 'DROP FUNCTION jrc_signature_connection_pin()'
    remove_column :jrc_backoffice_signature_integrations, :provider
  end

  private

  def create_connections
    create_table :jrc_backoffice_signature_connections do |t|
      t.references :account, null: false, foreign_key: true
      t.references :integration, null: false, foreign_key: { to_table: :jrc_backoffice_signature_integrations }
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      %i[public_id provider environment integration_key impersonated_user_id external_account_id credentials_purpose].each do |name|
        t.string name, null: false
      end
      t.text :encrypted_credentials, null: false
      t.integer :revision, null: false
      t.boolean :enabled, null: false, default: false
      t.datetime :authorization_checked_at
      t.datetime :connect_checked_at
      t.timestamps
    end
  end

  def index_connections
    add_index :jrc_backoffice_signature_connections, :public_id, unique: true, name: 'bo_signature_connection_public'
    add_index :jrc_backoffice_signature_connections, %i[integration_id revision], unique: true, name: 'bo_signature_connection_revision'
    add_index :jrc_backoffice_signature_connections, %i[account_id id], unique: true, name: 'bo_signature_connection_tenant_ref'
    add_foreign_key :jrc_backoffice_signature_connections, :jrc_backoffice_signature_integrations,
                    column: %i[account_id integration_id], primary_key: %i[account_id id], name: 'bo_signature_connection_tenant'
  end

  def copy_current_configuration
    execute <<~SQL.squish
      INSERT INTO jrc_backoffice_signature_connections
        (account_id, integration_id, created_by_id, public_id, provider, environment, integration_key, impersonated_user_id,
         external_account_id, encrypted_credentials, credentials_purpose, revision, enabled,
         authorization_checked_at, connect_checked_at, created_at, updated_at)
      SELECT account_id, id, created_by_id, public_id, provider, environment, integration_key, impersonated_user_id,
             external_account_id, encrypted_credentials, 'docusign:integration:' || public_id || ':revision:' || revision,
             revision, enabled, authorization_checked_at, connect_checked_at, created_at, updated_at
      FROM jrc_backoffice_signature_integrations
    SQL
  end

  def link_existing_notifications
    add_reference :jrc_backoffice_signature_notifications, :connection,
                  foreign_key: { to_table: :jrc_backoffice_signature_connections }
    add_foreign_key :jrc_backoffice_signature_notifications, :jrc_backoffice_signature_connections,
                    column: %i[account_id connection_id], primary_key: %i[account_id id], name: 'bo_signature_notification_connection_tenant'
    execute <<~SQL.squish
      UPDATE jrc_backoffice_signature_notifications AS event SET connection_id = connection.id
      FROM jrc_backoffice_signature_connections AS connection
      WHERE event.account_id = connection.account_id AND event.integration_id = connection.integration_id
        AND event.integration_revision = connection.revision
    SQL
  end

  def pin_configuration
    execute <<~SQL.squish
      CREATE FUNCTION jrc_signature_connection_pin() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF TG_OP = 'DELETE' OR (to_jsonb(NEW) - ARRAY['authorization_checked_at','connect_checked_at','updated_at'])
          IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['authorization_checked_at','connect_checked_at','updated_at']) THEN
          RAISE EXCEPTION 'Signature connection snapshots are immutable';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER jrc_signature_connection_pin BEFORE UPDATE OR DELETE ON jrc_backoffice_signature_connections
      FOR EACH ROW EXECUTE FUNCTION jrc_signature_connection_pin();
    SQL
  end
end
