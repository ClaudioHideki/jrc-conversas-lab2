-- Forward-only native queue/corporate scope evidence. This does not activate an automation.
-- No existing cc_ending_reason_* function/receipt is replaced.

CREATE FUNCTION cc_ending_action_scope_id(value jsonb) RETURNS bigint
LANGUAGE plpgsql IMMUTABLE AS $guard$
DECLARE identifier text;
BEGIN
  IF value IS NULL OR value = 'null'::jsonb THEN RETURN NULL; END IF;
  IF jsonb_typeof(value) NOT IN ('string', 'number') THEN RETURN NULL; END IF;
  identifier = value #>> '{}';
  IF identifier !~ '^[1-9][0-9]{0,18}$' THEN RETURN NULL; END IF;
  IF identifier::numeric > 9223372036854775807 THEN RETURN NULL; END IF;
  RETURN identifier::bigint;
END $guard$;

CREATE FUNCTION cc_ending_action_queue_scope_document(queue_key bigint) RETURNS jsonb
LANGUAGE plpgsql AS $guard$
DECLARE native_queue jrc_contact_center_queues%ROWTYPE;
  native_unit jrc_contact_center_units%ROWTYPE;
  issuer_value jsonb; business_value jsonb; issuer_key bigint; business_key bigint;
  scope_state text := 'unmapped'; scope_reason text := 'unmapped'; source_hash text;
BEGIN
  SELECT * INTO native_queue FROM jrc_contact_center_queues WHERE id = queue_key;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ending action queue unavailable'; END IF;
  SELECT * INTO native_unit FROM jrc_contact_center_units
    WHERE id = native_queue.unit_id AND account_id = native_queue.account_id;
  IF NOT FOUND THEN
    scope_state = 'invalid'; scope_reason = 'operational_unit_unavailable';
  ELSE
    issuer_value = native_unit.settings -> 'issuer_company_id';
    business_value = native_unit.settings -> 'business_unit_id';
    issuer_key = cc_ending_action_scope_id(issuer_value);
    business_key = cc_ending_action_scope_id(business_value);
    IF jsonb_typeof(native_unit.settings) IS DISTINCT FROM 'object' THEN
      scope_state = 'invalid'; scope_reason = 'invalid_scope_shape';
    ELSIF (issuer_value IS NULL OR issuer_value = 'null'::jsonb)
      AND (business_value IS NULL OR business_value = 'null'::jsonb) THEN
      scope_state = 'unmapped'; scope_reason = 'unmapped';
    ELSIF issuer_key IS NULL OR (business_value IS NOT NULL AND business_value <> 'null'::jsonb AND business_key IS NULL) THEN
      scope_state = 'invalid'; scope_reason = 'invalid_scope_identity';
      issuer_key = NULL; business_key = NULL;
    ELSIF NOT EXISTS (SELECT 1 FROM companies WHERE id = issuer_key AND account_id = native_queue.account_id
      AND relationship_type = 'internal' AND active IS TRUE) THEN
      scope_state = 'invalid'; scope_reason = 'issuer_unavailable'; issuer_key = NULL; business_key = NULL;
    ELSIF business_key IS NOT NULL AND NOT EXISTS (SELECT 1 FROM jrc_crm_business_units
      WHERE id = business_key AND account_id = native_queue.account_id AND company_id = issuer_key AND active IS TRUE) THEN
      scope_state = 'invalid'; scope_reason = 'business_unit_unavailable'; business_key = NULL;
    ELSE
      scope_state = 'mapped'; scope_reason = 'mapped';
    END IF;
  END IF;
  -- Hash only scope keys, never full operational settings or credentials.
  source_hash = encode(sha256(convert_to(jsonb_build_object('issuer', issuer_value, 'business', business_value,
    'settings_kind', jsonb_typeof(native_unit.settings))::text, 'UTF8')), 'hex');
  RETURN jsonb_build_object('version', 1, 'account_id', native_queue.account_id, 'source_queue_id', native_queue.id,
    'unit_id', native_queue.unit_id, 'issuer_company_id', issuer_key, 'business_unit_id', business_key,
    'scope_state', scope_state, 'scope_reason', scope_reason, 'raw_scope_sha256', source_hash);
END $guard$;

CREATE FUNCTION cc_ending_action_queue_scope_guard() RETURNS trigger
LANGUAGE plpgsql AS $guard$
DECLARE native_queue jrc_contact_center_queues%ROWTYPE;
  previous jrc_contact_center_ending_action_queue_scopes%ROWTYPE;
  document jsonb; captured timestamp without time zone;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id) THEN
      RAISE EXCEPTION 'Ending action queue scope history is immutable';
    END IF;
    RETURN OLD;
  END IF;
  IF TG_OP = 'UPDATE' THEN
    IF OLD.queue_id = OLD.source_queue_id AND NEW.queue_id IS NULL
      AND (to_jsonb(NEW) - 'queue_id') = (to_jsonb(OLD) - 'queue_id')
      AND NOT EXISTS (SELECT 1 FROM jrc_contact_center_queues WHERE id = OLD.queue_id) THEN RETURN NEW; END IF;
    RAISE EXCEPTION 'Ending action queue scope history is immutable';
  END IF;
  IF NEW.queue_id IS NOT NULL OR NEW.unit_id IS NOT NULL OR NEW.revision IS NOT NULL
    OR NEW.issuer_company_id IS NOT NULL OR NEW.business_unit_id IS NOT NULL OR NEW.scope_state IS NOT NULL
    OR NEW.scope_digest IS NOT NULL OR NEW.integrity_sha256 IS NOT NULL OR NEW.created_at IS NOT NULL
    OR NEW.payload IS DISTINCT FROM '{}'::jsonb THEN RAISE EXCEPTION 'Ending action scope provenance is server generated'; END IF;
  SELECT * INTO native_queue FROM jrc_contact_center_queues
    WHERE id = NEW.source_queue_id AND account_id = NEW.account_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ending action queue identity mismatch'; END IF;
  SELECT * INTO previous FROM jrc_contact_center_ending_action_queue_scopes
    WHERE account_id = NEW.account_id AND source_queue_id = NEW.source_queue_id ORDER BY revision DESC LIMIT 1;
  captured = timezone('UTC', clock_timestamp());
  IF previous.id IS NOT NULL AND captured <= previous.created_at THEN
    RAISE EXCEPTION 'Ending action scope clock order unavailable';
  END IF;
  document = cc_ending_action_queue_scope_document(native_queue.id);
  NEW.queue_id = native_queue.id;
  NEW.unit_id = (document ->> 'unit_id')::bigint;
  NEW.revision = COALESCE(previous.revision, 0) + 1;
  NEW.issuer_company_id = (document ->> 'issuer_company_id')::bigint;
  NEW.business_unit_id = (document ->> 'business_unit_id')::bigint;
  NEW.scope_state = document ->> 'scope_state';
  NEW.scope_digest = encode(sha256(convert_to(document::text, 'UTF8')), 'hex');
  NEW.payload = document;
  NEW.created_at = captured;
  NEW.integrity_sha256 = encode(sha256(convert_to(jsonb_build_object('account_id', NEW.account_id,
    'source_queue_id', NEW.source_queue_id, 'revision', NEW.revision, 'payload', NEW.payload,
    'created_at', NEW.created_at)::text, 'UTF8')), 'hex');
  RETURN NEW;
END $guard$;

CREATE TRIGGER cc_ending_action_queue_scope_immutable BEFORE INSERT OR UPDATE OR DELETE
  ON jrc_contact_center_ending_action_queue_scopes FOR EACH ROW EXECUTE FUNCTION cc_ending_action_queue_scope_guard();

CREATE FUNCTION cc_ending_action_capture_queue_scope(queue_key bigint) RETURNS bigint
LANGUAGE plpgsql AS $guard$
DECLARE native_queue jrc_contact_center_queues%ROWTYPE;
  previous jrc_contact_center_ending_action_queue_scopes%ROWTYPE;
  document jsonb; digest text; captured_key bigint;
BEGIN
  SELECT * INTO native_queue FROM jrc_contact_center_queues WHERE id = queue_key FOR UPDATE;
  IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM accounts WHERE id = native_queue.account_id) THEN RETURN NULL; END IF;
  document = cc_ending_action_queue_scope_document(native_queue.id);
  digest = encode(sha256(convert_to(document::text, 'UTF8')), 'hex');
  SELECT * INTO previous FROM jrc_contact_center_ending_action_queue_scopes
    WHERE account_id = native_queue.account_id AND source_queue_id = native_queue.id ORDER BY revision DESC LIMIT 1;
  IF previous.id IS NOT NULL AND previous.scope_digest = digest THEN RETURN previous.id; END IF;
  INSERT INTO jrc_contact_center_ending_action_queue_scopes(account_id, source_queue_id)
    VALUES(native_queue.account_id, native_queue.id) RETURNING id INTO captured_key;
  RETURN captured_key;
END $guard$;

CREATE FUNCTION cc_ending_action_queue_changed() RETURNS trigger
LANGUAGE plpgsql AS $guard$
BEGIN
  PERFORM cc_ending_action_capture_queue_scope(NEW.id);
  RETURN NEW;
END $guard$;

CREATE TRIGGER cc_ending_action_queue_scope_created AFTER INSERT ON jrc_contact_center_queues
  FOR EACH ROW EXECUTE FUNCTION cc_ending_action_queue_changed();
CREATE TRIGGER cc_ending_action_queue_scope_changed AFTER UPDATE OF unit_id, account_id ON jrc_contact_center_queues
  FOR EACH ROW WHEN (OLD.unit_id IS DISTINCT FROM NEW.unit_id OR OLD.account_id IS DISTINCT FROM NEW.account_id)
  EXECUTE FUNCTION cc_ending_action_queue_changed();

CREATE FUNCTION cc_ending_action_unit_scope_changed() RETURNS trigger
LANGUAGE plpgsql AS $guard$
DECLARE queue_key bigint; unit_key bigint;
BEGIN
  unit_key = CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END;
  FOR queue_key IN SELECT id FROM jrc_contact_center_queues WHERE unit_id = unit_key ORDER BY id LOOP
    PERFORM cc_ending_action_capture_queue_scope(queue_key);
  END LOOP;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $guard$;

CREATE TRIGGER cc_ending_action_unit_scope_changed AFTER UPDATE OF settings, account_id ON jrc_contact_center_units
  FOR EACH ROW WHEN (OLD.account_id IS DISTINCT FROM NEW.account_id
    OR jsonb_typeof(OLD.settings) IS DISTINCT FROM jsonb_typeof(NEW.settings)
    OR OLD.settings -> 'issuer_company_id' IS DISTINCT FROM NEW.settings -> 'issuer_company_id'
    OR OLD.settings -> 'business_unit_id' IS DISTINCT FROM NEW.settings -> 'business_unit_id')
  EXECUTE FUNCTION cc_ending_action_unit_scope_changed();
CREATE TRIGGER cc_ending_action_unit_scope_deleted AFTER DELETE ON jrc_contact_center_units
  FOR EACH ROW EXECUTE FUNCTION cc_ending_action_unit_scope_changed();

CREATE FUNCTION cc_ending_action_corporate_scope_changed() RETURNS trigger
LANGUAGE plpgsql AS $guard$
DECLARE resource_key bigint; setting_key text; queue_key bigint;
BEGIN
  resource_key = CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END;
  IF TG_TABLE_NAME = 'companies' THEN setting_key = 'issuer_company_id';
  ELSIF TG_TABLE_NAME = 'jrc_crm_business_units' THEN setting_key = 'business_unit_id';
  ELSE RAISE EXCEPTION 'Unknown ending action scope source'; END IF;
  FOR queue_key IN SELECT queues.id FROM jrc_contact_center_queues queues
    JOIN jrc_contact_center_units units ON units.id = queues.unit_id AND units.account_id = queues.account_id
    WHERE units.settings ->> setting_key = resource_key::text ORDER BY queues.id LOOP
    PERFORM cc_ending_action_capture_queue_scope(queue_key);
  END LOOP;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $guard$;

CREATE TRIGGER cc_ending_action_issuer_scope_changed AFTER UPDATE OF active, relationship_type, account_id ON companies
  FOR EACH ROW EXECUTE FUNCTION cc_ending_action_corporate_scope_changed();
CREATE TRIGGER cc_ending_action_issuer_scope_deleted AFTER DELETE ON companies
  FOR EACH ROW EXECUTE FUNCTION cc_ending_action_corporate_scope_changed();
CREATE TRIGGER cc_ending_action_business_scope_changed AFTER UPDATE OF company_id, account_id, active ON jrc_crm_business_units
  FOR EACH ROW EXECUTE FUNCTION cc_ending_action_corporate_scope_changed();
CREATE TRIGGER cc_ending_action_business_scope_deleted AFTER DELETE ON jrc_crm_business_units
  FOR EACH ROW EXECUTE FUNCTION cc_ending_action_corporate_scope_changed();

-- A pre-anchor event remains unattested. Never reconstruct a historical scope from current settings.
CREATE FUNCTION cc_ending_action_queue_scope_at(account_key bigint, queue_key bigint, observed_at timestamp without time zone)
RETURNS bigint LANGUAGE sql STABLE AS $guard$
  SELECT id FROM jrc_contact_center_ending_action_queue_scopes
  WHERE account_id = account_key AND source_queue_id = queue_key AND created_at <= observed_at
  ORDER BY created_at DESC, revision DESC LIMIT 1
$guard$;
