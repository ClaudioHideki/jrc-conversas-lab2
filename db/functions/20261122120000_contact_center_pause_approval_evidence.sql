-- Additive source evidence only. No policies, decisions, grants, provider calls or existing pause-table changes.
CREATE FUNCTION cc_pause_approval_evidence_guard() RETURNS trigger LANGUAGE plpgsql AS $guard$
DECLARE
  parent jrc_contact_center_deferred_pause_requests%ROWTYPE;
  root jrc_contact_center_pause_approval_reviews%ROWTYPE;
  item jsonb;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF NOT EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id) THEN RETURN OLD; END IF;
    RAISE EXCEPTION 'Pause approval evidence is immutable';
  END IF;
  IF TG_OP = 'UPDATE' THEN RAISE EXCEPTION 'Pause approval evidence is immutable'; END IF;
  IF TG_TABLE_NAME = 'jrc_contact_center_pause_approval_reviews' THEN
    SELECT * INTO parent FROM jrc_contact_center_deferred_pause_requests
      WHERE id = NEW.deferred_pause_request_id AND account_id = NEW.account_id;
    IF parent.id IS NULL OR parent.state <> 'pending'
      OR NEW.actor_account_user_id IS DISTINCT FROM parent.account_user_id
      OR NEW.actor_user_id IS DISTINCT FROM parent.actor_user_id
      OR NEW.payload -> 'version' IS DISTINCT FROM '1'::jsonb
      OR NEW.payload ->> 'request_id' IS DISTINCT FROM parent.request_id::text
      OR NEW.payload #>> '{intent,reason_code}' IS DISTINCT FROM parent.reason_code
      OR NEW.payload #>> '{intent,queue_id}' IS DISTINCT FROM parent.queue_id::text
      OR NEW.payload #>> '{intent,justification}' IS DISTINCT FROM parent.justification
      OR NEW.payload #>> '{selection,catalog_revision}' IS DISTINCT FROM parent.catalog_revision
      OR NEW.payload #>> '{selection,reason_label}' IS DISTINCT FROM parent.reason_label
      OR NEW.payload #>> '{coverage,account_id}' IS DISTINCT FROM NEW.account_id::text
      OR NEW.payload #>> '{coverage,actor_account_user_id}' IS DISTINCT FROM NEW.actor_account_user_id::text
      OR NEW.payload #>> '{coverage,actor_user_id}' IS DISTINCT FROM NEW.actor_user_id::text
      OR NEW.payload #> '{coverage,all_affected_units}' IS DISTINCT FROM 'true'::jsonb
      OR NEW.payload #> '{coverage,local_only}' IS DISTINCT FROM 'true'::jsonb
      OR NEW.payload #> '{coverage,provider_confirmed}' IS DISTINCT FROM 'false'::jsonb THEN
      RAISE EXCEPTION 'Pause approval native source mismatch';
    END IF;
    IF jsonb_typeof(NEW.payload #> '{coverage,groups}') IS DISTINCT FROM 'array'
      OR jsonb_typeof(NEW.payload #> '{coverage,units}') IS DISTINCT FROM 'array' THEN
      RAISE EXCEPTION 'Pause approval scope capture required';
    END IF;
    IF jsonb_array_length(NEW.payload #> '{coverage,groups}') = 0
      OR jsonb_array_length(NEW.payload #> '{coverage,units}') = 0 THEN
      RAISE EXCEPTION 'Pause approval scope capture required';
    END IF;
    RETURN NEW;
  END IF;
  SELECT * INTO root FROM jrc_contact_center_pause_approval_reviews WHERE id = NEW.review_id AND account_id = NEW.account_id;
  IF root.id IS NULL OR jsonb_typeof(NEW.unit_ids) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Pause approval owned scope required';
  END IF;
  IF jsonb_array_length(NEW.unit_ids) = 0 OR NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(root.payload #> '{coverage,groups}') AS captured
      WHERE captured ->> 'issuer_company_id' = NEW.issuer_company_id::text
        AND (captured ->> 'business_unit_id') IS NOT DISTINCT FROM NEW.business_unit_id::text
        AND captured -> 'unit_ids' = NEW.unit_ids
  ) THEN RAISE EXCEPTION 'Pause approval scope capture mismatch'; END IF;
  IF NOT EXISTS (SELECT 1 FROM companies WHERE id = NEW.issuer_company_id AND account_id = NEW.account_id
      AND relationship_type = 'internal' AND active)
    OR (NEW.business_unit_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM jrc_crm_business_units
      WHERE id = NEW.business_unit_id AND account_id = NEW.account_id AND company_id = NEW.issuer_company_id AND active)) THEN
    RAISE EXCEPTION 'Pause approval corporate source unavailable';
  END IF;
  FOR item IN SELECT value FROM jsonb_array_elements(NEW.unit_ids) LOOP
    IF NOT EXISTS (SELECT 1 FROM jrc_contact_center_units AS unit WHERE unit.account_id = NEW.account_id
      AND unit.id::text = (item #>> '{}') AND unit.status = 'active'
      AND unit.settings ->> 'issuer_company_id' = NEW.issuer_company_id::text
      AND (unit.settings ->> 'business_unit_id') IS NOT DISTINCT FROM NEW.business_unit_id::text) THEN
      RAISE EXCEPTION 'Pause approval operational unit mismatch';
    END IF;
  END LOOP;
  RETURN NEW;
END $guard$;

CREATE FUNCTION cc_pause_approval_scope_completeness() RETURNS trigger LANGUAGE plpgsql AS $guard$
DECLARE
  root_id bigint;
  owner_id bigint;
  root jrc_contact_center_pause_approval_reviews%ROWTYPE;
BEGIN
  IF TG_TABLE_NAME = 'jrc_contact_center_pause_approval_reviews' THEN
    IF TG_OP = 'DELETE' THEN root_id := OLD.id; owner_id := OLD.account_id;
    ELSE root_id := NEW.id; owner_id := NEW.account_id; END IF;
  ELSE
    IF TG_OP = 'DELETE' THEN root_id := OLD.review_id; owner_id := OLD.account_id;
    ELSE root_id := NEW.review_id; owner_id := NEW.account_id; END IF;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM accounts WHERE id = owner_id) THEN RETURN NULL; END IF;
  SELECT * INTO root FROM jrc_contact_center_pause_approval_reviews WHERE id = root_id AND account_id = owner_id;
  IF root.id IS NULL THEN RAISE EXCEPTION 'Pause approval owned review required'; END IF;
  IF (SELECT count(*) FROM jrc_contact_center_pause_approval_scopes WHERE review_id = root_id AND account_id = owner_id)
      <> jsonb_array_length(root.payload #> '{coverage,groups}') OR EXISTS (
    SELECT 1 FROM jsonb_array_elements(root.payload #> '{coverage,groups}') AS captured WHERE NOT EXISTS (
      SELECT 1 FROM jrc_contact_center_pause_approval_scopes AS scope WHERE scope.review_id = root_id AND scope.account_id = owner_id
        AND scope.issuer_company_id::text = captured ->> 'issuer_company_id'
        AND scope.business_unit_id::text IS NOT DISTINCT FROM (captured ->> 'business_unit_id')
        AND scope.unit_ids = captured -> 'unit_ids'
    )
  ) THEN RAISE EXCEPTION 'Pause approval requires every captured scope'; END IF;
  RETURN NULL;
END $guard$;

CREATE TRIGGER cc_pause_approval_review_guard BEFORE INSERT OR UPDATE OR DELETE ON jrc_contact_center_pause_approval_reviews
  FOR EACH ROW EXECUTE FUNCTION cc_pause_approval_evidence_guard();
CREATE TRIGGER cc_pause_approval_scope_guard BEFORE INSERT OR UPDATE OR DELETE ON jrc_contact_center_pause_approval_scopes
  FOR EACH ROW EXECUTE FUNCTION cc_pause_approval_evidence_guard();
CREATE CONSTRAINT TRIGGER cc_pause_approval_review_complete AFTER INSERT OR DELETE ON jrc_contact_center_pause_approval_reviews
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION cc_pause_approval_scope_completeness();
CREATE CONSTRAINT TRIGGER cc_pause_approval_scope_complete AFTER INSERT OR DELETE ON jrc_contact_center_pause_approval_scopes
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION cc_pause_approval_scope_completeness();
