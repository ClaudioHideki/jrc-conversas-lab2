class CreateRelationshipRetentionHistory < ActiveRecord::Migration[7.1]
  def up
    create_table :jrc_relationship_retention_coverages do |t|
      t.references :account, null: false, type: :integer, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.datetime :started_at, null: false
    end
    create_table :jrc_relationship_retention_states do |t|
      t.references :account, null: false, type: :integer, foreign_key: { on_delete: :cascade }
      t.string :customer_key, null: false
      t.bigint :assignment_id, null: false
      t.bigint :owner_id
      t.bigint :team_id
      t.bigint :business_unit_id
      t.jsonb :facts, null: false
      t.datetime :observed_at, null: false
    end
    add_index :jrc_relationship_retention_states, [:account_id, :customer_key, :observed_at, :id], name: 'rel_retention_customer_time'
    add_check_constraint :jrc_relationship_retention_states,
      "customer_key ~ '^(company|contact):[1-9][0-9]*$' AND jsonb_typeof(facts) = 'object'", name: 'rel_retention_identity'
    execute <<~SQL
      CREATE FUNCTION jrc_rel_retention_immutable() RETURNS trigger AS $$
      BEGIN
        IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id) THEN RETURN OLD; END IF;
        RAISE EXCEPTION 'Retention history is immutable' USING ERRCODE = '23514';
      END; $$ LANGUAGE plpgsql;
      CREATE TRIGGER rel_retention_immutable BEFORE UPDATE OR DELETE ON jrc_relationship_retention_states
        FOR EACH ROW EXECUTE FUNCTION jrc_rel_retention_immutable();
      CREATE TRIGGER rel_retention_coverage_immutable BEFORE UPDATE OR DELETE ON jrc_relationship_retention_coverages
        FOR EACH ROW EXECUTE FUNCTION jrc_rel_retention_immutable();

      -- Only actual observations from the existing native tables. No guessed past.
      CREATE FUNCTION jrc_rel_retention_observe(a jsonb, removed boolean DEFAULT false, baseline boolean DEFAULT false) RETURNS void AS $$
      DECLARE account_key integer; identity_key text; kind text; master_present boolean; active boolean;
              registered text; groups jsonb; facts jsonb; previous jsonb;
      BEGIN
        account_key := (a->>'account_id')::integer;
        IF NOT EXISTS (SELECT 1 FROM accounts WHERE id = account_key) THEN RETURN; END IF;
        PERFORM pg_advisory_xact_lock(1280528947, account_key);
        IF NOT baseline AND NOT EXISTS (SELECT 1 FROM jrc_relationship_retention_coverages WHERE account_id = account_key) THEN RETURN; END IF;
        IF a->>'company_id' IS NOT NULL THEN
          kind := 'company'; identity_key := 'company:' || (a->>'company_id');
          SELECT true, c.active INTO master_present, active FROM companies c
            WHERE c.account_id = account_key AND c.id = (a->>'company_id')::bigint;
        ELSE
          kind := 'contact'; identity_key := 'contact:' || (a->>'contact_id');
          SELECT true, c.registration_status INTO master_present, registered FROM contacts c
            WHERE c.account_id = account_key AND c.id = (a->>'contact_id')::bigint;
        END IF;
        SELECT COALESCE(jsonb_agg(g.id ORDER BY g.id), '[]'::jsonb) INTO groups
          FROM jrc_relationship_portfolio_groups g
          JOIN jrc_relationship_portfolio_group_assignments l ON l.portfolio_group_id = g.id AND l.account_id = g.account_id
          WHERE l.account_id = account_key AND l.assignment_id = (a->>'id')::bigint AND l.active AND g.status = 'active';
        facts := jsonb_build_object('customer_key', identity_key, 'customer_type', kind,
          'source_present', COALESCE(master_present, false) AND NOT removed,
          'status', CASE WHEN removed THEN 'inactive' ELSE a->>'status' END,
          'master_active', active, 'registration_status', registered,
          'owner_id', a->'owner_id', 'team_id', a->'team_id', 'business_unit_id', a->'business_unit_id',
          'assignment_id', (a->>'id')::bigint, 'portfolio_ids', groups);
        SELECT s.facts INTO previous FROM jrc_relationship_retention_states s
          WHERE s.account_id = account_key AND s.customer_key = identity_key ORDER BY s.observed_at DESC, s.id DESC LIMIT 1;
        IF previous IS NOT DISTINCT FROM facts THEN RETURN; END IF;
        INSERT INTO jrc_relationship_retention_states(account_id, customer_key, assignment_id, owner_id, team_id, business_unit_id, facts, observed_at)
          VALUES(account_key, identity_key, (a->>'id')::bigint, (a->>'owner_id')::bigint, (a->>'team_id')::bigint,
                 (a->>'business_unit_id')::bigint, facts, timezone('UTC', clock_timestamp()));
      END; $$ LANGUAGE plpgsql;

      CREATE FUNCTION jrc_rel_retention_assignment_capture() RETURNS trigger AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN PERFORM jrc_rel_retention_observe(to_jsonb(OLD), true); RETURN OLD; END IF;
        IF TG_OP = 'UPDATE' AND (OLD.account_id, OLD.company_id, OLD.contact_id) IS DISTINCT FROM (NEW.account_id, NEW.company_id, NEW.contact_id)
          THEN PERFORM jrc_rel_retention_observe(to_jsonb(OLD), true); END IF;
        PERFORM jrc_rel_retention_observe(to_jsonb(NEW), false); RETURN NEW;
      END; $$ LANGUAGE plpgsql;
      CREATE TRIGGER rel_retention_assignment_capture AFTER INSERT OR UPDATE OR DELETE ON jrc_relationship_assignments
        FOR EACH ROW EXECUTE FUNCTION jrc_rel_retention_assignment_capture();

      CREATE FUNCTION jrc_rel_retention_source_capture() RETURNS trigger AS $$
      DECLARE source jsonb; row_data record; linked bigint;
      BEGIN
        source := CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(NEW) END;
        IF TG_TABLE_NAME = 'companies' THEN
          FOR row_data IN SELECT * FROM jrc_relationship_assignments WHERE account_id = (source->>'account_id')::integer
            AND company_id = (source->>'id')::bigint LOOP PERFORM jrc_rel_retention_observe(to_jsonb(row_data), false); END LOOP;
        ELSIF TG_TABLE_NAME = 'contacts' THEN
          FOR row_data IN SELECT * FROM jrc_relationship_assignments WHERE account_id = (source->>'account_id')::integer
            AND contact_id = (source->>'id')::bigint LOOP PERFORM jrc_rel_retention_observe(to_jsonb(row_data), false); END LOOP;
        ELSIF TG_TABLE_NAME = 'jrc_relationship_portfolio_groups' THEN
          FOR row_data IN SELECT a.* FROM jrc_relationship_assignments a JOIN jrc_relationship_portfolio_group_assignments l
            ON l.assignment_id = a.id AND l.account_id = a.account_id WHERE l.portfolio_group_id = (source->>'id')::bigint
            AND a.account_id = (source->>'account_id')::integer LOOP PERFORM jrc_rel_retention_observe(to_jsonb(row_data), false); END LOOP;
        ELSE
          linked := (source->>'assignment_id')::bigint;
          FOR row_data IN SELECT * FROM jrc_relationship_assignments WHERE account_id = (source->>'account_id')::integer
            AND id = linked LOOP PERFORM jrc_rel_retention_observe(to_jsonb(row_data), false); END LOOP;
          IF TG_OP = 'UPDATE' AND OLD.assignment_id IS DISTINCT FROM NEW.assignment_id THEN
            FOR row_data IN SELECT * FROM jrc_relationship_assignments WHERE account_id = OLD.account_id
              AND id = OLD.assignment_id LOOP PERFORM jrc_rel_retention_observe(to_jsonb(row_data), false); END LOOP;
          END IF;
        END IF;
        IF TG_OP = 'DELETE' THEN RETURN OLD; END IF; RETURN NEW;
      END; $$ LANGUAGE plpgsql;
      CREATE TRIGGER rel_retention_company_capture AFTER UPDATE OF active OR DELETE ON companies
        FOR EACH ROW EXECUTE FUNCTION jrc_rel_retention_source_capture();
      CREATE TRIGGER rel_retention_contact_capture AFTER UPDATE OF registration_status OR DELETE ON contacts
        FOR EACH ROW EXECUTE FUNCTION jrc_rel_retention_source_capture();
      CREATE TRIGGER rel_retention_group_capture AFTER UPDATE OF status ON jrc_relationship_portfolio_groups
        FOR EACH ROW EXECUTE FUNCTION jrc_rel_retention_source_capture();
      CREATE TRIGGER rel_retention_link_capture AFTER INSERT OR UPDATE OR DELETE ON jrc_relationship_portfolio_group_assignments
        FOR EACH ROW EXECUTE FUNCTION jrc_rel_retention_source_capture();
    SQL
  end

  def down
    execute 'DROP TRIGGER IF EXISTS rel_retention_link_capture ON jrc_relationship_portfolio_group_assignments'
    execute 'DROP TRIGGER IF EXISTS rel_retention_group_capture ON jrc_relationship_portfolio_groups'
    execute 'DROP TRIGGER IF EXISTS rel_retention_contact_capture ON contacts'
    execute 'DROP TRIGGER IF EXISTS rel_retention_company_capture ON companies'
    execute 'DROP TRIGGER IF EXISTS rel_retention_assignment_capture ON jrc_relationship_assignments'
    execute 'DROP FUNCTION IF EXISTS jrc_rel_retention_source_capture()'
    execute 'DROP FUNCTION IF EXISTS jrc_rel_retention_assignment_capture()'
    execute 'DROP FUNCTION IF EXISTS jrc_rel_retention_observe(jsonb, boolean, boolean)'
    drop_table :jrc_relationship_retention_states
    drop_table :jrc_relationship_retention_coverages
    execute 'DROP FUNCTION IF EXISTS jrc_rel_retention_immutable()'
  end
end
