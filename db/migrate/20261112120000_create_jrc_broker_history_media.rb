class CreateJrcBrokerHistoryMedia < ActiveRecord::Migration[7.1]
  # One additive DDL transaction; the revocation table is a counter, not an event log.
  # Keep the multi-statement function/trigger SQL verbatim for schema parity.
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Rails/SquishedSQLHeredocs
  def up
    create_table :jrc_broker_history_media do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.references :access_token, foreign_key: { on_delete: :nullify }
      t.string :access_token_sha256, null: false, limit: 64
      t.references :message, foreign_key: { on_delete: :cascade }
      t.references :receipt, foreign_key: { to_table: :jrc_broker_history_receipts, on_delete: :cascade }
      t.references :blob, null: false, foreign_key: { to_table: :active_storage_blobs }
      t.uuid :organization_id, :integration_id, :instance_id, :history_account_identity, :reference_id, null: false
      t.integer :destination_revision, null: false
      t.jsonb :descriptor, null: false
      t.string :descriptor_hash, null: false, limit: 64
      t.string :state, null: false, default: 'RESERVED'
      t.integer :attempts, null: false, default: 0
      t.datetime :next_attempt_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
      t.string :last_error
      t.timestamps
    end
    add_index :jrc_broker_history_media, [:account_id, :inbox_id, :integration_id, :history_account_identity, :reference_id],
              unique: true, name: 'jrc_history_media_source_identity'
    add_index :jrc_broker_history_media, :message_id, unique: true, where: 'message_id IS NOT NULL', name: 'jrc_history_media_message'
    add_index :jrc_broker_history_media, :next_attempt_at, where: "state='ATTACH_PENDING'", name: 'jrc_history_media_pending'
    add_check_constraint :jrc_broker_history_media, "state IN('RESERVED','STORED','ATTACH_PENDING','READY')", name: 'jrc_history_media_state'
    add_check_constraint :jrc_broker_history_media, "descriptor_hash ~ '^[a-f0-9]{64}$' AND destination_revision>0 AND attempts>=0",
                         name: 'jrc_history_media_descriptor'
    add_check_constraint :jrc_broker_history_media, "access_token_sha256 ~ '^[a-f0-9]{64}$'", name: 'jrc_history_media_token_fence'
    add_check_constraint :jrc_broker_history_media,
                         "(state IN('RESERVED','STORED') AND message_id IS NULL AND receipt_id IS NULL) OR " \
                         "(state IN('ATTACH_PENDING','READY') AND message_id IS NOT NULL AND receipt_id IS NOT NULL)",
                         name: 'jrc_history_media_attachment'

    # An inbox-sized revocation fence avoids hashing/scanning its entire history
    # on every metadata refresh. Inserts do not revoke previously admitted pages.
    create_table :jrc_broker_history_visibilities do |t| # rubocop:disable Rails/CreateTableWithTimestamps
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.bigint :revision, null: false, default: 0
    end
    execute <<~SQL
      CREATE OR REPLACE FUNCTION public.jrc_history_visibility_revoke() RETURNS trigger
        LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
      BEGIN
        IF OLD.record_kind = 'CHAT' AND EXISTS (
          SELECT 1 FROM public.inboxes b JOIN public.accounts a ON a.id=b.account_id
          WHERE b.id=OLD.inbox_id AND a.id=OLD.account_id
        ) THEN
          INSERT INTO public.jrc_broker_history_visibilities(account_id,inbox_id,revision)
          VALUES(OLD.account_id,OLD.inbox_id,1)
          ON CONFLICT(inbox_id) DO UPDATE SET revision=jrc_broker_history_visibilities.revision+1;
        END IF;
        RETURN OLD;
      END;
      $$;
      CREATE TRIGGER jrc_history_visibility_revoke AFTER DELETE ON public.jrc_broker_history_receipts
        FOR EACH ROW EXECUTE FUNCTION public.jrc_history_visibility_revoke();
    SQL
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Rails/SquishedSQLHeredocs

  def down
    raise ActiveRecord::IrreversibleMigration, 'Pause historical media; preserve objects, receipts and pending obligations'
  end
end
