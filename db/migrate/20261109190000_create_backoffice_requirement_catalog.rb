class CreateBackofficeRequirementCatalog < ActiveRecord::Migration[7.1]
  def up
    create_table :jrc_backoffice_requirement_rules do |t|
      t.references :account, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.references :business_unit, foreign_key: { to_table: :jrc_crm_business_units }
      t.references :product, foreign_key: { to_table: :jrc_crm_products }
      t.string :rule_key, null: false
      t.integer :version, null: false
      t.string :state, null: false, default: 'active'
      t.string :operation
      t.string :customer_kind
      t.jsonb :definition, null: false
      t.text :reason, null: false
      t.datetime :created_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
    end
    add_index :jrc_backoffice_requirement_rules, %i[account_id rule_key version], unique: true, name: 'bo_req_rule_revision'
    add_check_constraint :jrc_backoffice_requirement_rules, "version > 0 AND state IN ('active','archived')", name: 'bo_req_rule_state'
    add_check_constraint :jrc_backoffice_requirement_rules, "jsonb_typeof(definition) = 'object'", name: 'bo_req_rule_object'

    create_table :jrc_backoffice_requirement_plans do |t|
      t.references :account, null: false, foreign_key: true
      t.references :backoffice_request, null: false, foreign_key: { to_table: :jrc_crm_backoffice_requests }, index: false
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.integer :version, null: false
      t.jsonb :entries, null: false, default: []
      t.jsonb :source_facts, null: false, default: {}
      t.string :digest, null: false, limit: 64
      t.text :reason, null: false
      t.datetime :created_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
    end
    add_index :jrc_backoffice_requirement_plans, %i[backoffice_request_id version], unique: true, name: 'bo_req_plan_revision'
    add_check_constraint :jrc_backoffice_requirement_plans, "version > 0 AND jsonb_typeof(entries) = 'array' AND jsonb_array_length(entries) <= 100 AND jsonb_typeof(source_facts) = 'object'", name: 'bo_req_plan_shape'

    create_table :jrc_backoffice_requirement_responses do |t|
      t.references :account, null: false, foreign_key: true
      t.references :requirement_plan, null: false, foreign_key: { to_table: :jrc_backoffice_requirement_plans }, index: false
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.string :requirement_key, null: false
      t.integer :revision, null: false
      t.jsonb :payload, null: false
      t.text :reason, null: false
      t.datetime :created_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
    end
    add_index :jrc_backoffice_requirement_responses, %i[requirement_plan_id requirement_key revision], unique: true, name: 'bo_req_response_revision'
    add_check_constraint :jrc_backoffice_requirement_responses, "revision > 0 AND jsonb_typeof(payload) = 'object'", name: 'bo_req_response_shape'

    execute <<~SQL
      CREATE FUNCTION jrc_bo_requirement_guard() RETURNS trigger AS $$
      DECLARE
        parent_account bigint;
        item jsonb;
        captured jsonb;
      BEGIN
        IF TG_OP IN ('UPDATE', 'DELETE') THEN
          RAISE EXCEPTION 'Backoffice requirement revisions are immutable';
        END IF;
        IF TG_TABLE_NAME = 'jrc_backoffice_requirement_rules' THEN
          IF NOT EXISTS (SELECT 1 FROM account_users WHERE account_id=NEW.account_id AND user_id=NEW.created_by_id)
          THEN RAISE EXCEPTION 'Requirement creator account mismatch'; END IF;
          IF NEW.business_unit_id IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM jrc_crm_business_units WHERE id=NEW.business_unit_id AND account_id=NEW.account_id
          ) THEN RAISE EXCEPTION 'Requirement unit account mismatch'; END IF;
          IF NEW.product_id IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM jrc_crm_products WHERE id=NEW.product_id AND account_id=NEW.account_id
          ) THEN RAISE EXCEPTION 'Requirement product account mismatch'; END IF;
        ELSIF TG_TABLE_NAME = 'jrc_backoffice_requirement_plans' THEN
          SELECT account_id INTO parent_account FROM jrc_crm_backoffice_requests WHERE id=NEW.backoffice_request_id;
          IF parent_account IS DISTINCT FROM NEW.account_id THEN RAISE EXCEPTION 'Requirement plan account mismatch'; END IF;
          IF NOT EXISTS (SELECT 1 FROM account_users WHERE account_id=NEW.account_id AND user_id=NEW.created_by_id)
          THEN RAISE EXCEPTION 'Requirement creator account mismatch'; END IF;
          FOR item IN SELECT value FROM jsonb_array_elements(NEW.entries) LOOP
            IF NOT EXISTS (SELECT 1 FROM jrc_backoffice_requirement_rules
                WHERE id=(item->>'rule_id')::bigint AND account_id=NEW.account_id
                  AND rule_key=item->>'key' AND version=(item->>'rule_version')::int
                  AND definition=item->'definition'
                  AND COALESCE(to_jsonb(customer_kind), 'null'::jsonb)=item->'scope'->'customer_kind')
            THEN RAISE EXCEPTION 'Requirement rule snapshot mismatch'; END IF;
          END LOOP;
        ELSE
          SELECT account_id INTO parent_account FROM jrc_backoffice_requirement_plans WHERE id=NEW.requirement_plan_id;
          IF parent_account IS DISTINCT FROM NEW.account_id THEN RAISE EXCEPTION 'Requirement response account mismatch'; END IF;
          IF NOT EXISTS (SELECT 1 FROM account_users WHERE account_id=NEW.account_id AND user_id=NEW.actor_id)
          THEN RAISE EXCEPTION 'Requirement respondent account mismatch'; END IF;
          SELECT value->'definition' INTO captured
            FROM jrc_backoffice_requirement_plans, jsonb_array_elements(entries)
            WHERE id=NEW.requirement_plan_id AND value->>'key'=NEW.requirement_key;
          IF captured IS NULL THEN RAISE EXCEPTION 'Requirement is not in plan'; END IF;
          IF COALESCE(captured->>'requirement_kind', captured->>'kind') = 'information' THEN
            IF NOT (NEW.payload ? 'value') OR (NEW.payload - 'value') <> '{}'::jsonb
            THEN RAISE EXCEPTION 'Invalid information response'; END IF;
          ELSIF COALESCE(captured->>'requirement_kind', captured->>'kind') = 'validation'
              AND captured->>'source'='manual_review' THEN
            IF COALESCE(NEW.payload->>'decision','') NOT IN ('approved','rejected') OR (NEW.payload - 'decision') <> '{}'::jsonb
            THEN RAISE EXCEPTION 'Invalid manual review'; END IF;
          ELSE RAISE EXCEPTION 'Native evidence cannot be supplied manually'; END IF;
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL
    %w[rules plans responses].each do |suffix|
      execute "CREATE TRIGGER jrc_bo_req_#{suffix}_guard BEFORE INSERT OR UPDATE OR DELETE ON jrc_backoffice_requirement_#{suffix} " \
              'FOR EACH ROW EXECUTE FUNCTION jrc_bo_requirement_guard()'
    end
  end

  def down
    drop_table :jrc_backoffice_requirement_responses
    drop_table :jrc_backoffice_requirement_plans
    drop_table :jrc_backoffice_requirement_rules
    execute 'DROP FUNCTION jrc_bo_requirement_guard()'
  end
end
