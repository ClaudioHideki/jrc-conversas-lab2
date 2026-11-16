class CreateJrcBrokerLiveReceipts < ActiveRecord::Migration[7.1]
  # One additive DDL transaction; preserve function SQL verbatim for schema parity.
  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Rails/SquishedSQLHeredocs
  def up
    create_table :jrc_broker_live_receipts, id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.references :account, null: false, foreign_key: true
      t.references :inbox, null: false, foreign_key: true
      t.references :user, foreign_key: { on_delete: :nullify }
      t.references :access_token, foreign_key: { on_delete: :nullify }
      t.string :access_token_sha256, null: false, limit: 64
      t.references :message, foreign_key: true
      t.references :blob, foreign_key: { to_table: :active_storage_blobs }
      t.uuid :organization_id, :integration_id, :instance_id, :broker_message_id, null: false
      t.bigint :destination_revision, :conversation_id, null: false
      t.jsonb :envelope, null: false
      t.string :request_hash, null: false, limit: 64
      t.string :state, null: false
      t.datetime :published_at
      t.binary :staged_bytes
      t.integer :attempts, null: false, default: 0
      t.datetime :next_attempt_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
      t.string :last_error
      t.timestamps
    end
    add_index :jrc_broker_live_receipts, [:account_id, :inbox_id, :organization_id, :integration_id, :instance_id, :broker_message_id],
              unique: true, name: 'jrc_live_receive_identity'
    add_index :jrc_broker_live_receipts, :next_attempt_at, where: "state='MEDIA_PENDING'", name: 'jrc_live_pending'
    add_index :jrc_broker_live_receipts, :message_id, unique: true, where: 'message_id IS NOT NULL', name: 'jrc_live_message'
    add_check_constraint :jrc_broker_live_receipts,
                         "request_hash ~ '^[a-f0-9]{64}$' AND access_token_sha256 ~ '^[a-f0-9]{64}$' AND " \
                         'destination_revision>0 AND conversation_id>0 AND attempts>=0', name: 'jrc_live_identity_bounds'
    add_check_constraint :jrc_broker_live_receipts,
                         "(state='MEDIA_PENDING' AND message_id IS NULL AND blob_id IS NOT NULL AND " \
                         'staged_bytes IS NOT NULL AND published_at IS NULL AND octet_length(staged_bytes) BETWEEN 1 AND 16777216) OR ' \
                         "(state='PERSISTED' AND message_id IS NOT NULL AND staged_bytes IS NULL)", name: 'jrc_live_custody'
    execute <<~SQL
      CREATE OR REPLACE FUNCTION public.jrc_live_receipt_immutable() RETURNS trigger
        LANGUAGE plpgsql SET search_path=pg_catalog,public AS $$
      BEGIN
        IF ROW(NEW.id,NEW.account_id,NEW.inbox_id,NEW.organization_id,NEW.integration_id,NEW.instance_id,
               NEW.broker_message_id,NEW.destination_revision,NEW.conversation_id,NEW.envelope,NEW.request_hash,
               NEW.blob_id,NEW.access_token_sha256,NEW.created_at)
           IS DISTINCT FROM
           ROW(OLD.id,OLD.account_id,OLD.inbox_id,OLD.organization_id,OLD.integration_id,OLD.instance_id,
               OLD.broker_message_id,OLD.destination_revision,OLD.conversation_id,OLD.envelope,OLD.request_hash,
               OLD.blob_id,OLD.access_token_sha256,OLD.created_at)
           OR (NEW.user_id IS DISTINCT FROM OLD.user_id AND NEW.user_id IS NOT NULL)
           OR (NEW.access_token_id IS DISTINCT FROM OLD.access_token_id AND NEW.access_token_id IS NOT NULL)
           OR (OLD.state='PERSISTED' AND ROW(NEW.state,NEW.message_id,NEW.staged_bytes,NEW.published_at)
                                      IS DISTINCT FROM ROW(OLD.state,OLD.message_id,OLD.staged_bytes,OLD.published_at))
           OR (OLD.state='MEDIA_PENDING' AND NEW.state='MEDIA_PENDING' AND NEW.staged_bytes IS DISTINCT FROM OLD.staged_bytes)
        THEN RAISE EXCEPTION 'JRC_LIVE_RECEIPT_IMMUTABLE'; END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER jrc_live_receipt_immutable BEFORE UPDATE ON public.jrc_broker_live_receipts
        FOR EACH ROW EXECUTE FUNCTION public.jrc_live_receipt_immutable();
    SQL
    add_column :jrc_broker_history_receipts, :origin_context, :jsonb
    execute <<~SQL
      CREATE OR REPLACE FUNCTION public.jrc_history_origin_immutable() RETURNS trigger
        LANGUAGE plpgsql SET search_path=pg_catalog,public AS $$
      BEGIN
        IF NEW.origin_context IS DISTINCT FROM OLD.origin_context THEN
          RAISE EXCEPTION 'JRC_HISTORY_ORIGIN_IMMUTABLE';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER jrc_history_origin_immutable BEFORE UPDATE ON public.jrc_broker_history_receipts
        FOR EACH ROW EXECUTE FUNCTION public.jrc_history_origin_immutable();
    SQL
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize, Rails/SquishedSQLHeredocs

  def down
    raise ActiveRecord::IrreversibleMigration, 'Pause native admission; retain LIVE receipts, pending escrow and private KEEP objects'
  end
end
