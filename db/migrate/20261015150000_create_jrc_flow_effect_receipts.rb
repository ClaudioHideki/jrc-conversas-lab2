class CreateJrcFlowEffectReceipts < ActiveRecord::Migration[7.1]
  def up
    add_column :conversations, :jrc_effect_control_revision, :bigint, null: false, default: 0
    create_receipt_table
    add_receipt_constraints
    install_conversation_trigger
    install_message_trigger
    install_contact_inbox_trigger
    install_contact_trigger
    install_inbox_trigger
    install_receipt_trigger
  end

  def down
    execute <<~SQL.squish
      DROP TRIGGER jrc_effect_conversation_control ON conversations;
      DROP TRIGGER jrc_effect_message_control ON messages;
      DROP TRIGGER jrc_effect_contact_inbox_control ON contact_inboxes;
      DROP TRIGGER jrc_effect_contact_control ON contacts;
      DROP TRIGGER IF EXISTS jrc_effect_inbox_control ON inboxes;
      DROP TRIGGER jrc_effect_receipt_immutable ON jrc_flow_effect_receipts;
      DROP FUNCTION jrc_effect_conversation_control();
      DROP FUNCTION jrc_effect_message_control();
      DROP FUNCTION jrc_effect_contact_inbox_control();
      DROP FUNCTION jrc_effect_contact_control();
      DROP FUNCTION IF EXISTS jrc_effect_inbox_control();
      DROP FUNCTION jrc_effect_receipt_immutable();
    SQL
    drop_table :jrc_flow_effect_receipts
    remove_column :conversations, :jrc_effect_control_revision
  end

  private

  def create_receipt_table
    create_table :jrc_flow_effect_receipts do |t|
      %i[account inbox conversation].each { |name| t.references name, null: false, foreign_key: { on_delete: :cascade } }
      t.uuid :organization_id, :operation_id, null: false
      t.bigint :remote_conversation_id, :remote_contact_id, :contact_inbox_id, :actor_user_id, null: false
      t.string :routing_source_hash, :request_hash, :dispatch_proof_hash, null: false, limit: 64
      t.string :operation, null: false
      t.bigint :resource_id, :message_id
      t.string :resource_revision, limit: 64
      t.bigint :control_revision_before, :control_revision_after, null: false
      t.timestamps
    end
    add_index :jrc_flow_effect_receipts, [:account_id, :organization_id, :operation_id], unique: true, name: 'jrc_effect_receipt_identity'
    add_index :jrc_flow_effect_receipts, :message_id, unique: true, where: 'message_id IS NOT NULL'
  end

  def add_receipt_constraints
    add_check_constraint :jrc_flow_effect_receipts, "operation IN ('tag','attribute','note','resolve')", name: 'jrc_effect_operation'
    add_check_constraint :jrc_flow_effect_receipts,
                         "(operation = 'note') = (message_id IS NOT NULL)", name: 'jrc_effect_message'
    add_check_constraint :jrc_flow_effect_receipts,
                         "(operation IN ('tag','attribute') AND resource_id IS NOT NULL AND resource_revision IS NOT NULL) OR " \
                         "(operation NOT IN ('tag','attribute') AND resource_id IS NULL AND resource_revision IS NULL)",
                         name: 'jrc_effect_resource'
    add_check_constraint :jrc_flow_effect_receipts,
                         'control_revision_before >= 0 AND control_revision_after >= control_revision_before', name: 'jrc_effect_revision'
  end

  def install_receipt_trigger
    execute <<~SQL.squish
      CREATE FUNCTION jrc_effect_receipt_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF NEW IS DISTINCT FROM OLD THEN RAISE EXCEPTION 'jrc_effect_receipt_immutable' USING ERRCODE = '23514'; END IF;
        RETURN NEW;
      END $$;
      CREATE TRIGGER jrc_effect_receipt_immutable BEFORE UPDATE ON jrc_flow_effect_receipts
        FOR EACH ROW EXECUTE FUNCTION jrc_effect_receipt_immutable();
    SQL
  end

  def install_conversation_trigger
    execute <<~SQL.squish
      CREATE FUNCTION jrc_effect_conversation_control() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF ROW(NEW.account_id, NEW.inbox_id, NEW.contact_id, NEW.contact_inbox_id, NEW.assignee_id,
               NEW.assignee_agent_bot_id, NEW.team_id, NEW.status, NEW.custom_attributes, NEW.cached_label_list)
           IS DISTINCT FROM
           ROW(OLD.account_id, OLD.inbox_id, OLD.contact_id, OLD.contact_inbox_id, OLD.assignee_id,
               OLD.assignee_agent_bot_id, OLD.team_id, OLD.status, OLD.custom_attributes, OLD.cached_label_list)
           OR NEW.jrc_effect_control_revision IS DISTINCT FROM OLD.jrc_effect_control_revision THEN
          NEW.jrc_effect_control_revision := OLD.jrc_effect_control_revision + 1;
        END IF;
        RETURN NEW;
      END $$;
      CREATE TRIGGER jrc_effect_conversation_control BEFORE UPDATE ON conversations
        FOR EACH ROW EXECUTE FUNCTION jrc_effect_conversation_control();
    SQL
  end

  def install_message_trigger
    # Message.store(JSON) persists a JSON string; direct SQL drivers may persist an object.
    execute <<~SQL.squish
      CREATE FUNCTION jrc_effect_message_control() RETURNS trigger LANGUAGE plpgsql AS $$
      DECLARE attributes jsonb;
      BEGIN
        IF NEW.message_type <> 1 THEN RETURN NEW; END IF;
        attributes := NEW.content_attributes::jsonb;
        IF jsonb_typeof(attributes) = 'string' THEN
          BEGIN attributes := (attributes #>> '{}')::jsonb;
          EXCEPTION WHEN invalid_text_representation THEN attributes := '{"external_echo":true}'::jsonb; END;
        END IF;
        IF NEW.sender_type = 'User' OR COALESCE(attributes->'external_echo', 'null'::jsonb)
           NOT IN ('null'::jsonb, 'false'::jsonb, '""'::jsonb, '[]'::jsonb, '{}'::jsonb) THEN
          UPDATE conversations SET jrc_effect_control_revision = jrc_effect_control_revision + 1 WHERE id = NEW.conversation_id;
        END IF;
        RETURN NEW;
      END $$;
      CREATE TRIGGER jrc_effect_message_control BEFORE INSERT ON messages
        FOR EACH ROW EXECUTE FUNCTION jrc_effect_message_control();
    SQL
  end

  def install_contact_inbox_trigger
    execute <<~SQL.squish
      CREATE FUNCTION jrc_effect_contact_inbox_control() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF ROW(NEW.source_id, NEW.contact_id, NEW.inbox_id) IS DISTINCT FROM ROW(OLD.source_id, OLD.contact_id, OLD.inbox_id) THEN
          PERFORM id FROM conversations WHERE contact_inbox_id = OLD.id ORDER BY id FOR UPDATE;
          UPDATE conversations SET jrc_effect_control_revision = jrc_effect_control_revision + 1 WHERE contact_inbox_id = OLD.id;
        END IF;
        RETURN NEW;
      END $$;
      CREATE TRIGGER jrc_effect_contact_inbox_control BEFORE UPDATE ON contact_inboxes
        FOR EACH ROW EXECUTE FUNCTION jrc_effect_contact_inbox_control();
    SQL
  end

  def install_contact_trigger
    execute <<~SQL.squish
      CREATE FUNCTION jrc_effect_contact_control() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF ROW(NEW.account_id, NEW.email, NEW.phone_number, NEW.identifier)
           IS DISTINCT FROM ROW(OLD.account_id, OLD.email, OLD.phone_number, OLD.identifier) THEN
          PERFORM id FROM conversations WHERE contact_id = OLD.id ORDER BY id FOR UPDATE;
          UPDATE conversations SET jrc_effect_control_revision = jrc_effect_control_revision + 1 WHERE contact_id = OLD.id;
        END IF;
        RETURN NEW;
      END $$;
      CREATE TRIGGER jrc_effect_contact_control BEFORE UPDATE ON contacts
        FOR EACH ROW EXECUTE FUNCTION jrc_effect_contact_control();
    SQL
  end

  def install_inbox_trigger
    execute <<~SQL.squish
      CREATE FUNCTION jrc_effect_inbox_control() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF ROW(NEW.account_id, NEW.channel_id, NEW.channel_type) IS DISTINCT FROM ROW(OLD.account_id, OLD.channel_id, OLD.channel_type) THEN
          PERFORM id FROM conversations WHERE inbox_id = OLD.id ORDER BY id FOR UPDATE;
          UPDATE conversations SET jrc_effect_control_revision = jrc_effect_control_revision + 1 WHERE inbox_id = OLD.id;
        END IF;
        RETURN NEW;
      END $$;
      CREATE TRIGGER jrc_effect_inbox_control BEFORE UPDATE ON inboxes
        FOR EACH ROW EXECUTE FUNCTION jrc_effect_inbox_control();
    SQL
  end
end
