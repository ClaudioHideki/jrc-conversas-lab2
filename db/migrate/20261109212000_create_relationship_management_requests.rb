class CreateRelationshipManagementRequests < ActiveRecord::Migration[7.1]
  def up
    create_table :jrc_relationship_management_requests do |t|
      t.references :account, type: :integer, null: false, foreign_key: { on_delete: :cascade }
      t.references :requester, type: :integer, null: false, foreign_key: { to_table: :users }
      t.references :analyst, type: :integer, foreign_key: { to_table: :users }
      t.references :assignment, foreign_key: { to_table: :jrc_relationship_assignments }
      t.references :batch_review, foreign_key: { to_table: :jrc_relationship_batch_reviews }
      t.references :resolution_event, foreign_key: { to_table: :jrc_crm_audit_events }
      t.string :kind, null: false
      t.string :state, null: false, default: 'pending'
      t.text :reason, null: false
      t.string :idempotency_key, null: false
      t.string :input_digest, null: false
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :jrc_relationship_management_requests, [:account_id, :requester_id, :idempotency_key], unique: true, name: 'rel_mgmt_request_key'
    add_check_constraint :jrc_relationship_management_requests, "(kind = 'transfer' AND assignment_id IS NOT NULL AND analyst_id IS NULL) OR (kind IN ('suspend','restore') AND assignment_id IS NULL AND analyst_id IS NOT NULL)", name: 'rel_mgmt_request_origin'
    add_check_constraint :jrc_relationship_management_requests, "(state = 'pending' AND batch_review_id IS NULL AND resolution_event_id IS NULL) OR (state = 'routed' AND ((kind = 'transfer' AND batch_review_id IS NOT NULL AND resolution_event_id IS NULL) OR (kind IN ('suspend','restore') AND resolution_event_id IS NOT NULL AND batch_review_id IS NULL)))", name: 'rel_mgmt_request_state'
    execute <<~SQL
      CREATE FUNCTION jrc_rel_management_guard() RETURNS trigger AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          IF NOT EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id) THEN RETURN OLD; END IF;
          RAISE EXCEPTION 'Management request retained' USING ERRCODE = '23514';
        END IF;
        IF TG_OP = 'UPDATE' AND
          ((OLD.id,OLD.created_at,OLD.account_id,OLD.requester_id,OLD.assignment_id,OLD.analyst_id,OLD.kind,OLD.reason,OLD.input_digest,OLD.idempotency_key) IS DISTINCT FROM
           (NEW.id,NEW.created_at,NEW.account_id,NEW.requester_id,NEW.assignment_id,NEW.analyst_id,NEW.kind,NEW.reason,NEW.input_digest,NEW.idempotency_key)
           OR (OLD.state='routed' AND to_jsonb(OLD) IS DISTINCT FROM to_jsonb(NEW))) THEN
          RAISE EXCEPTION 'Management request immutable origin or receipt' USING ERRCODE = '23514';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM account_users WHERE account_id=NEW.account_id AND user_id=NEW.requester_id) OR
          (NEW.analyst_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM account_users WHERE account_id=NEW.account_id AND user_id=NEW.analyst_id)) OR
          (NEW.assignment_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM jrc_relationship_assignments WHERE account_id=NEW.account_id AND id=NEW.assignment_id)) OR
          (NEW.batch_review_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM jrc_relationship_batch_reviews WHERE account_id=NEW.account_id AND id=NEW.batch_review_id)) OR
          (NEW.resolution_event_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM jrc_crm_audit_events WHERE account_id=NEW.account_id AND id=NEW.resolution_event_id)) THEN
          RAISE EXCEPTION 'Management request account mismatch' USING ERRCODE='23514';
        END IF;
        RETURN NEW;
      END; $$ LANGUAGE plpgsql;
      CREATE TRIGGER rel_management_guard BEFORE INSERT OR UPDATE OR DELETE ON jrc_relationship_management_requests FOR EACH ROW EXECUTE FUNCTION jrc_rel_management_guard();
    SQL
  end
  def down
    drop_table :jrc_relationship_management_requests
    execute 'DROP FUNCTION IF EXISTS jrc_rel_management_guard()'
  end
end
