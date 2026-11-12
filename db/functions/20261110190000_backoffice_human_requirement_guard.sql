CREATE OR REPLACE FUNCTION jrc_bo_requirement_guard() RETURNS trigger AS $$
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
    IF (CASE WHEN captured->>'kind'='conditional' THEN captured->>'requirement_kind' ELSE captured->>'kind' END) = 'information' THEN
      IF NOT (NEW.payload ? 'value') OR (NEW.payload - 'value') <> '{}'::jsonb
      THEN RAISE EXCEPTION 'Invalid information response'; END IF;
    ELSIF (CASE WHEN captured->>'kind'='conditional' THEN captured->>'requirement_kind' ELSE captured->>'kind' END) = 'validation'
        AND captured->>'source'='manual_review' THEN
      IF COALESCE(NEW.payload->>'decision','') NOT IN ('approved','rejected') OR (NEW.payload - 'decision') <> '{}'::jsonb
      THEN RAISE EXCEPTION 'Invalid manual review'; END IF;
    ELSIF (CASE WHEN captured->>'kind'='conditional' THEN captured->>'requirement_kind' ELSE captured->>'kind' END) IN ('consultation','confirmation','human_activity') THEN
      IF jsonb_typeof(NEW.payload->'decision') IS DISTINCT FROM 'string'
         OR jsonb_typeof(NEW.payload->'note') IS DISTINCT FROM 'string'
         OR (NEW.payload - ARRAY['decision','note']) <> '{}'::jsonb
         OR char_length(NEW.payload->>'note') NOT BETWEEN 1 AND 4000
         OR (NEW.payload->>'note') !~ '[^[:space:]]'
         OR ((CASE WHEN captured->>'kind'='conditional' THEN captured->>'requirement_kind' ELSE captured->>'kind' END)='confirmation' AND NEW.payload->>'decision' NOT IN ('confirmed','rejected'))
         OR ((CASE WHEN captured->>'kind'='conditional' THEN captured->>'requirement_kind' ELSE captured->>'kind' END) IN ('consultation','human_activity') AND NEW.payload->>'decision' NOT IN ('completed','rejected'))
      THEN RAISE EXCEPTION 'Invalid explicit human response'; END IF;
      IF NOT (
        COALESCE(captured->'reviewer_ids','[]'::jsonb) @> jsonb_build_array(NEW.actor_id)
        OR EXISTS (
          SELECT 1 FROM team_members m JOIN teams t ON t.id=m.team_id
          WHERE m.user_id=NEW.actor_id AND t.account_id=NEW.account_id
            AND COALESCE(captured->'reviewer_team_ids','[]'::jsonb) @> jsonb_build_array(t.id)
        )
      ) THEN RAISE EXCEPTION 'A configured human reviewer is required'; END IF;
    ELSE RAISE EXCEPTION 'Native evidence cannot be supplied manually'; END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
