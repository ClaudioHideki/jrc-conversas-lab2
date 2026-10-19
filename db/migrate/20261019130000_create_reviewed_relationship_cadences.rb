class CreateReviewedRelationshipCadences < ActiveRecord::Migration[7.1]
  def up
    create_enrollments
    create_steps
    add_tenant_references
    install_enrollment_guard
    install_step_guard
  end

  def down
    drop_table :jrc_relationship_cadence_steps
    drop_table :jrc_relationship_cadence_enrollments
    execute 'DROP FUNCTION rel_cadence_guard(); DROP FUNCTION rel_cadence_step_guard()'
  end

  private

  def create_enrollments
    create_table :jrc_relationship_cadence_enrollments do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :actor_id, :assignment_id, :batch_review_id, :conversation_id, null: false
      t.jsonb :snapshot, null: false
      t.datetime :starts_at, null: false
      t.string :state, null: false, default: 'active'
      t.string :stop_reason
      t.bigint :revision, null: false, default: 1
      t.timestamps
    end
    add_index :jrc_relationship_cadence_enrollments, %i[account_id id], unique: true, name: 'rel_cadence_tenant_ref'
    add_index :jrc_relationship_cadence_enrollments, %i[account_id batch_review_id assignment_id], unique: true, name: 'rel_cadence_once'
    add_check_constraint :jrc_relationship_cadence_enrollments,
                         "state IN ('active','completed','stopped') AND revision>0 AND (state='stopped')=(stop_reason IS NOT NULL) " \
                         'AND octet_length(snapshot::text)<=1048576', name: 'rel_cadence_state'
  end

  def create_steps
    create_table :jrc_relationship_cadence_steps do |t|
      t.bigint :account_id, :cadence_enrollment_id, null: false
      t.integer :ordinal, null: false
      t.jsonb :definition, null: false
      t.datetime :due_at, null: false
      t.string :state, null: false, default: 'pending'
      t.jsonb :receipt
      t.timestamps
    end
    add_index :jrc_relationship_cadence_steps, %i[cadence_enrollment_id ordinal], unique: true, name: 'rel_cadence_step_once'
    add_index :jrc_relationship_cadence_steps, :due_at, where: "state='pending'", name: 'rel_cadence_due'
    add_check_constraint :jrc_relationship_cadence_steps,
                         "state IN ('pending','applied','canceled') AND ordinal BETWEEN 0 AND 49 AND (state='applied')=(receipt IS NOT NULL)",
                         name: 'rel_cadence_step_state'
  end

  def add_tenant_references
    add_foreign_key :jrc_relationship_cadence_enrollments, :jrc_relationship_batch_reviews,
                    column: %i[account_id batch_review_id], primary_key: %i[account_id id], on_delete: :cascade, name: 'rel_cadence_review'
    add_foreign_key :jrc_relationship_cadence_enrollments, :jrc_relationship_assignments,
                    column: %i[account_id assignment_id], primary_key: %i[account_id id], on_delete: :cascade, name: 'rel_cadence_customer'
    add_foreign_key :jrc_relationship_cadence_steps, :jrc_relationship_cadence_enrollments,
                    column: %i[account_id cadence_enrollment_id], primary_key: %i[account_id id], on_delete: :cascade,
                    name: 'rel_cadence_step_tenant'
  end

  def install_enrollment_guard
    execute <<~SQL.squish
      CREATE FUNCTION rel_cadence_guard() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF (to_jsonb(NEW)-ARRAY['state','revision','stop_reason','updated_at']) IS DISTINCT FROM
           (to_jsonb(OLD)-ARRAY['state','revision','stop_reason','updated_at']) OR NEW.revision<>OLD.revision+1 OR OLD.state<>'active' THEN
          RAISE EXCEPTION 'Cadence snapshot is immutable';
        END IF;
        RETURN NEW;
      END; $$;
      CREATE TRIGGER rel_cadence_immutable BEFORE UPDATE ON jrc_relationship_cadence_enrollments
        FOR EACH ROW EXECUTE FUNCTION rel_cadence_guard();
    SQL
  end

  def install_step_guard
    execute <<~SQL.squish
      CREATE FUNCTION rel_cadence_step_guard() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF (to_jsonb(NEW)-ARRAY['state','receipt','updated_at']) IS DISTINCT FROM
           (to_jsonb(OLD)-ARRAY['state','receipt','updated_at']) OR OLD.state<>'pending' OR NEW.state='pending' THEN
          RAISE EXCEPTION 'Cadence receipt is immutable';
        END IF;
        RETURN NEW;
      END; $$;
      CREATE TRIGGER rel_cadence_receipt_immutable BEFORE UPDATE ON jrc_relationship_cadence_steps
        FOR EACH ROW EXECUTE FUNCTION rel_cadence_step_guard();
    SQL
  end
end
