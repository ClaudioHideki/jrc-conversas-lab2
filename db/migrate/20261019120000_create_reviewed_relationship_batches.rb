class CreateReviewedRelationshipBatches < ActiveRecord::Migration[7.1]
  def up
    create_reviews
    create_items
    add_constraints
    install_review_guard
    install_item_guard
  end

  def down
    drop_table :jrc_relationship_batch_items
    drop_table :jrc_relationship_batch_reviews
    execute 'DROP FUNCTION IF EXISTS rel_batch_review_guard(); DROP FUNCTION IF EXISTS rel_batch_item_guard()'
    remove_index :jrc_relationship_assignments, name: 'rel_assignment_batch_ref'
  end

  private

  def create_reviews
    create_table :jrc_relationship_batch_reviews do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :actor_id, null: false
      t.uuid :request_id, null: false
      t.jsonb :inputs, :snapshot, null: false
      t.string :digest, null: false, limit: 64
      t.string :state, null: false, default: 'previewed'
      t.bigint :revision, null: false, default: 1
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :jrc_relationship_batch_reviews, %i[account_id id], unique: true, name: 'rel_batch_tenant_ref'
    add_index :jrc_relationship_batch_reviews, %i[account_id actor_id request_id], unique: true, name: 'rel_batch_request_once'
  end

  def create_items
    add_index :jrc_relationship_assignments, %i[account_id id], unique: true, name: 'rel_assignment_batch_ref'
    create_table :jrc_relationship_batch_items do |t|
      t.bigint :account_id, :batch_review_id, :assignment_id, null: false
      t.integer :ordinal, null: false
      t.string :state, null: false, default: 'pending'
      t.jsonb :receipt
      t.string :error_code
      t.timestamps
    end
    add_index :jrc_relationship_batch_items, %i[account_id batch_review_id assignment_id], unique: true, name: 'rel_batch_customer_once'
    add_index :jrc_relationship_batch_items, %i[batch_review_id ordinal], unique: true, name: 'rel_batch_order_once'
    add_foreign_key :jrc_relationship_batch_items, :jrc_relationship_batch_reviews,
                    column: %i[account_id batch_review_id], primary_key: %i[account_id id], on_delete: :cascade, name: 'rel_batch_item_tenant'
    add_foreign_key :jrc_relationship_batch_items, :jrc_relationship_assignments,
                    column: %i[account_id assignment_id], primary_key: %i[account_id id], on_delete: :cascade, name: 'rel_batch_item_customer'
  end

  def add_constraints
    add_check_constraint :jrc_relationship_batch_reviews,
                         "state IN ('previewed','running','completed','canceled','attention') AND revision>0", name: 'rel_batch_state'
    add_check_constraint :jrc_relationship_batch_reviews,
                         "digest ~ '^[a-f0-9]{64}$' AND octet_length(snapshot::text)<=1048576 AND octet_length(inputs::text)<=65536",
                         name: 'rel_batch_bounds'
    add_check_constraint :jrc_relationship_batch_items,
                         "state IN ('pending','applied','failed','canceled') AND ordinal BETWEEN 0 AND 49 " \
                         "AND (state='applied')=(receipt IS NOT NULL)",
                         name: 'rel_batch_item_state'
  end

  def install_review_guard
    execute <<~SQL.squish
      CREATE FUNCTION rel_batch_review_guard() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF (to_jsonb(NEW)-ARRAY['state','revision','updated_at']) IS DISTINCT FROM
           (to_jsonb(OLD)-ARRAY['state','revision','updated_at']) OR NEW.revision<>OLD.revision+1 OR
           OLD.state IN ('completed','canceled','attention') OR
           (OLD.state='previewed' AND NEW.state NOT IN ('running','canceled')) THEN
          RAISE EXCEPTION 'Reviewed batch snapshot is immutable';
        END IF;
        RETURN NEW;
      END; $$;
      CREATE TRIGGER rel_batch_review_immutable BEFORE UPDATE ON jrc_relationship_batch_reviews
        FOR EACH ROW EXECUTE FUNCTION rel_batch_review_guard();
    SQL
  end

  def install_item_guard
    execute <<~SQL.squish
      CREATE FUNCTION rel_batch_item_guard() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF OLD.state<>'pending' OR NEW.state NOT IN ('applied','failed','canceled') OR
          (to_jsonb(NEW)-ARRAY['state','receipt','error_code','updated_at']) IS DISTINCT FROM
          (to_jsonb(OLD)-ARRAY['state','receipt','error_code','updated_at']) THEN
          RAISE EXCEPTION 'Batch receipt is immutable';
        END IF;
        RETURN NEW;
      END; $$;
      CREATE TRIGGER rel_batch_item_immutable BEFORE UPDATE ON jrc_relationship_batch_items
        FOR EACH ROW EXECUTE FUNCTION rel_batch_item_guard();
    SQL
  end
end
