# Keep assignment-only v1 snapshots/receipts unchanged. A master-company subject
# gains its assignment reference only when native creation and its receipt commit.
class AddMasterSubjectsToReviewedRelationshipBatches < ActiveRecord::Migration[7.1]
  RECEIPT_GUARD = <<~SQL.squish.freeze
    CREATE OR REPLACE FUNCTION rel_batch_item_guard() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      IF OLD.company_id IS NULL THEN
        IF OLD.state<>'pending' OR NEW.state NOT IN ('applied','failed','canceled') OR
          (to_jsonb(NEW)-ARRAY['state','receipt','error_code','updated_at']) IS DISTINCT FROM
          (to_jsonb(OLD)-ARRAY['state','receipt','error_code','updated_at']) THEN
          RAISE EXCEPTION 'Batch receipt is immutable';
        END IF;
        RETURN NEW;
      END IF;
      IF OLD.state<>'pending' OR NEW.state NOT IN ('applied','failed','canceled') OR
        (to_jsonb(NEW)-ARRAY['state','receipt','error_code','updated_at','assignment_id']) IS DISTINCT FROM
        (to_jsonb(OLD)-ARRAY['state','receipt','error_code','updated_at','assignment_id']) THEN
        RAISE EXCEPTION 'Master batch receipt is immutable';
      END IF;
      IF NEW.state='applied' AND (
        NEW.assignment_id IS NULL OR
        NEW.receipt->>'operation' IS DISTINCT FROM 'master_allocation' OR
        NEW.receipt->>'company_id' IS DISTINCT FROM NEW.company_id::text OR
        NEW.receipt->>'assignment_id' IS DISTINCT FROM NEW.assignment_id::text OR
        NOT EXISTS (SELECT 1 FROM jrc_relationship_assignments a WHERE a.id=NEW.assignment_id
          AND a.account_id=NEW.account_id AND a.company_id=NEW.company_id)
      ) THEN
        RAISE EXCEPTION 'Master batch receipt must identify its exact native company allocation';
      END IF;
      RETURN NEW;
    END; $$;
  SQL
  private_constant :RECEIPT_GUARD

  def up
    add_column :jrc_relationship_batch_items, :company_id, :bigint
    change_column_null :jrc_relationship_batch_items, :assignment_id, true
    add_index :jrc_relationship_batch_items, %i[account_id batch_review_id company_id], unique: true, name: 'rel_batch_master_once'
    add_foreign_key :jrc_relationship_batch_items, :companies, column: %i[account_id company_id], primary_key: %i[account_id id],
                                                               name: 'rel_batch_master_tenant'
    add_check_constraint :jrc_relationship_batch_items,
                         '(company_id IS NULL AND assignment_id IS NOT NULL) OR ' \
                         "(company_id IS NOT NULL AND ((state='applied' AND assignment_id IS NOT NULL) OR " \
                         "(state<>'applied' AND assignment_id IS NULL)))", name: 'rel_batch_subject_shape'
    install_master_insert_guard
    install_receipt_guard
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Retain additive subject columns and immutable master batch history; do not erase reviewed records'
  end

  private

  def install_master_insert_guard
    execute <<~SQL.squish
      CREATE FUNCTION rel_batch_master_insert_guard() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF NEW.company_id IS NOT NULL AND
          (NEW.state<>'pending' OR NEW.assignment_id IS NOT NULL OR NOT EXISTS (
            SELECT 1 FROM jrc_relationship_batch_reviews r WHERE r.id=NEW.batch_review_id
              AND r.account_id=NEW.account_id AND r.inputs->>'operation'='master_allocation'
          )) THEN
          RAISE EXCEPTION 'Master allocation subject requires a pending native master review';
        END IF;
        RETURN NEW;
      END; $$;
      CREATE TRIGGER rel_batch_master_subject_insert BEFORE INSERT ON jrc_relationship_batch_items
        FOR EACH ROW EXECUTE FUNCTION rel_batch_master_insert_guard();
    SQL
  end

  def install_receipt_guard
    execute RECEIPT_GUARD
  end
end
