-- Private, uninstalled next increment. Reuse the existing immutable call-start
-- pin; do not duplicate it or rewrite its historical migration/trigger.
-- Requires two owned leg columns and their receipt/migration tests, not yet installed.

CREATE FUNCTION cc_ending_action_leg_guard() RETURNS trigger
LANGUAGE plpgsql AS $guard$
DECLARE selected_id bigint;
  started timestamp without time zone;
  definition jsonb;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.ending_action_scope_version_id IS DISTINCT FROM OLD.ending_action_scope_version_id
      OR NEW.ending_action_captured_started_at IS DISTINCT FROM OLD.ending_action_captured_started_at
      OR (OLD.ending_action_scope_version_id IS NOT NULL AND
        (NEW.account_id, NEW.call_session_id) IS DISTINCT FROM (OLD.account_id, OLD.call_session_id)) THEN
      RAISE EXCEPTION 'Call leg ending action origin is immutable';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.ending_action_scope_version_id IS NOT NULL OR NEW.ending_action_captured_started_at IS NOT NULL THEN
    RAISE EXCEPTION 'Call leg ending action origin is server generated';
  END IF;
  SELECT ending_reason_captured_started_at INTO started FROM jrc_contact_center_call_sessions
    WHERE id = NEW.call_session_id AND account_id = NEW.account_id AND ending_reason_version_id IS NOT NULL;
  IF NOT FOUND OR started IS NULL THEN RETURN NEW; END IF;
  SELECT private_definition INTO definition FROM jrc_contact_center_ending_action_versions
    WHERE account_id = NEW.account_id AND created_at <= started ORDER BY created_at DESC, revision DESC LIMIT 1;
  IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(definition -> 'entries') rule
    WHERE rule -> 'active' = 'true'::jsonb
      AND rule ->> 'execution_mode' IN ('automatic', 'agent_confirmation')) THEN
    RETURN NEW;
  END IF;
  -- Capturing evidence does not enable effects; a future executor still needs
  -- its explicit server-issued readiness in this exact pinned version.
  -- Unknown queue at the observed leg creation stays without evidence. Do not fill it
  -- from the session's later current queue or from a provider correction.
  SELECT id INTO selected_id FROM jrc_contact_center_ending_action_queue_scopes
    WHERE account_id = NEW.account_id AND source_queue_id = NEW.queue_id AND created_at <= NEW.started_at
    ORDER BY created_at DESC, revision DESC LIMIT 1;
  NEW.ending_action_scope_version_id = selected_id;
  NEW.ending_action_captured_started_at = CASE WHEN selected_id IS NULL THEN NULL ELSE NEW.started_at END;
  RETURN NEW;
END $guard$;

CREATE TRIGGER cc_ending_action_leg_capture BEFORE INSERT OR UPDATE ON jrc_contact_center_call_legs
  FOR EACH ROW EXECUTE FUNCTION cc_ending_action_leg_guard();

-- Private, unapplied next increment. No migration creates the referenced origin table or loads these guards yet.
-- The existing ending-reason BEFORE trigger supplies its native snapshot first;
-- this AFTER capture never rewrites that historical trigger or copies notes/answers.

CREATE FUNCTION cc_ending_action_origin_guard() RETURNS trigger
LANGUAGE plpgsql AS $guard$
DECLARE source jrc_contact_center_agent_state_events%ROWTYPE;
  qualification jrc_contact_center_qualifications%ROWTYPE;
  session jrc_contact_center_call_sessions%ROWTYPE;
  leg jrc_contact_center_call_legs%ROWTYPE;
  scope jrc_contact_center_ending_action_queue_scopes%ROWTYPE;
  version jrc_contact_center_ending_action_versions%ROWTYPE;
  person account_users%ROWTYPE;
  snapshot jsonb;
BEGIN
  IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id) THEN RETURN OLD; END IF;
  IF TG_OP = 'UPDATE' AND OLD.qualification_id IS NOT NULL AND NEW.qualification_id IS NULL
    AND (to_jsonb(NEW) - 'qualification_id') = (to_jsonb(OLD) - 'qualification_id')
    AND NOT EXISTS (SELECT 1 FROM jrc_contact_center_qualifications WHERE id = OLD.qualification_id) THEN
    RETURN NEW;
  END IF;
  IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'Ending action original evidence is immutable'; END IF;
  IF NEW.source_qualification_id IS NOT NULL OR NEW.qualification_id IS NOT NULL
    OR NEW.call_session_id IS NOT NULL OR NEW.call_leg_id IS NOT NULL
    OR NEW.actor_account_user_id IS NOT NULL OR NEW.actor_user_id IS NOT NULL
    OR NEW.version_id IS NOT NULL OR NEW.ending_reason_catalog_id IS NOT NULL
    OR NEW.queue_scope_version_id IS NOT NULL OR NEW.queue_id IS NOT NULL OR NEW.unit_id IS NOT NULL
    OR NEW.issuer_company_id IS NOT NULL OR NEW.business_unit_id IS NOT NULL
    OR NEW.integrity_sha256 IS NOT NULL OR NEW.created_at IS NOT NULL OR NEW.private_origin_evidence IS DISTINCT FROM '{}'::jsonb THEN
    RAISE EXCEPTION 'Ending action original evidence is server generated';
  END IF;
  SELECT * INTO source FROM jrc_contact_center_agent_state_events
    WHERE id = NEW.origin_event_id AND account_id = NEW.account_id;
  IF NOT FOUND OR source.state IS DISTINCT FROM 'acw' OR source.source IS DISTINCT FROM 'jrc_conversas' THEN
    RAISE EXCEPTION 'Ending action native origin event unavailable';
  END IF;
  snapshot = source.metadata -> 'ending_reason_snapshot_v1';
  IF snapshot IS NULL OR snapshot -> 'required' IS DISTINCT FROM 'true'::jsonb THEN RETURN NULL; END IF;
  SELECT * INTO qualification FROM jrc_contact_center_qualifications
    WHERE id::text = source.metadata ->> 'qualification_id' AND account_id = source.account_id
      AND account_user_id = source.account_user_id AND channel = 'voice' AND completed_at IS NULL;
  IF NOT FOUND OR source.external_event_id IS DISTINCT FROM 'qualification:' || qualification.id::text || ':pending' THEN
    RETURN NULL;
  END IF;
  SELECT * INTO session FROM jrc_contact_center_call_sessions
    WHERE id = qualification.call_session_id AND account_id = source.account_id;
  IF NOT FOUND OR session.ending_reason_captured_started_at IS NULL OR session.ending_reason_version_id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO leg FROM jrc_contact_center_call_legs
    WHERE id::text = snapshot ->> 'call_leg_id' AND account_id = source.account_id
      AND call_session_id = session.id AND account_user_id = qualification.account_user_id AND answered_at IS NOT NULL;
  IF NOT FOUND OR leg.ending_action_scope_version_id IS NULL THEN RETURN NULL; END IF;
  IF session.status NOT IN ('ended', 'failed') AND leg.status NOT IN ('ended', 'failed', 'transferred') THEN RETURN NULL; END IF;
  SELECT * INTO scope FROM jrc_contact_center_ending_action_queue_scopes
    WHERE id = leg.ending_action_scope_version_id AND account_id = source.account_id;
  IF NOT FOUND OR scope.scope_state IS DISTINCT FROM 'mapped' OR scope.issuer_company_id IS NULL THEN RETURN NULL; END IF;
  IF scope.source_queue_id IS DISTINCT FROM leg.queue_id
    OR snapshot ->> 'queue_id' IS DISTINCT FROM scope.source_queue_id::text
    OR snapshot ->> 'unit_id' IS DISTINCT FROM scope.unit_id::text
    OR snapshot ->> 'catalogue_id' IS DISTINCT FROM session.ending_reason_version_id::text THEN
    RETURN NULL;
  END IF;
  -- Reuse the existing database-immutable first-observed call start. Effective
  -- rule times are generated by the private ledger's database guard; no caller
  -- date, current mutable call timestamp or retrospective permission is used.
  SELECT * INTO version FROM jrc_contact_center_ending_action_versions
    WHERE account_id = source.account_id AND created_at <= session.ending_reason_captured_started_at
    ORDER BY created_at DESC, revision DESC LIMIT 1;
  IF NOT FOUND THEN RETURN NULL; END IF;
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(version.private_definition -> 'entries') rule
    WHERE rule -> 'active' = 'true'::jsonb AND rule ->> 'queue_id' = scope.source_queue_id::text
      AND rule ->> 'execution_mode' IN ('automatic', 'agent_confirmation')
      AND rule #>> '{scope,queue_scope_version_id}' = scope.id::text
      AND rule #>> '{scope,integrity_sha256}' = scope.integrity_sha256) THEN
    RETURN NULL;
  END IF;
  SELECT * INTO person FROM account_users WHERE id = qualification.account_user_id AND account_id = source.account_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ending action original actor unavailable'; END IF;
  NEW.qualification_id = qualification.id;
  NEW.source_qualification_id = qualification.id;
  NEW.call_session_id = session.id;
  NEW.call_leg_id = leg.id;
  NEW.actor_account_user_id = person.id;
  NEW.actor_user_id = person.user_id;
  NEW.version_id = version.id;
  NEW.ending_reason_catalog_id = session.ending_reason_version_id;
  NEW.queue_scope_version_id = scope.id;
  NEW.queue_id = scope.source_queue_id;
  NEW.unit_id = scope.unit_id;
  NEW.issuer_company_id = scope.issuer_company_id;
  NEW.business_unit_id = scope.business_unit_id;
  NEW.created_at = timezone('UTC', clock_timestamp());
  NEW.private_origin_evidence = jsonb_build_object('version', 1, 'source_qualification_id', qualification.id,
    'call_session_id', session.id, 'call_leg_id', leg.id, 'origin_event_id', source.id,
    'leg_terminal_state', leg.status, 'session_state_at_capture', session.status,
    'actor_account_user_id', person.id, 'actor_user_id', person.user_id,
    'contact_id', session.contact_id, 'company_id', session.company_id,
    'rule_version_id', version.id, 'ending_reason_catalog_id', session.ending_reason_version_id,
    'queue_scope_version_id', scope.id, 'scope_integrity_sha256', scope.integrity_sha256,
    'queue_id', scope.source_queue_id, 'unit_id', scope.unit_id,
    'issuer_company_id', scope.issuer_company_id, 'business_unit_id', scope.business_unit_id,
    'captured_call_started_at', session.ending_reason_captured_started_at,
    'captured_leg_started_at', leg.ending_action_captured_started_at);
  NEW.integrity_sha256 = encode(sha256(convert_to(jsonb_build_object('account_id', NEW.account_id,
    'origin_event_id', NEW.origin_event_id, 'payload', NEW.private_origin_evidence, 'created_at', NEW.created_at)::text, 'UTF8')), 'hex');
  RETURN NEW;
END $guard$;

-- This is evidence, not arming. A future executor must require its server-issued
-- execution_token in the exact pinned version; an unarmed origin stays unarmed
-- even if a later version explicitly enables the same logical rule.

CREATE TRIGGER cc_ending_action_origin_immutable BEFORE INSERT OR UPDATE OR DELETE
  ON jrc_contact_center_ending_action_origins FOR EACH ROW EXECUTE FUNCTION cc_ending_action_origin_guard();

CREATE FUNCTION cc_ending_action_capture_pending() RETURNS trigger
LANGUAGE plpgsql AS $guard$
BEGIN
  IF NEW.state IS DISTINCT FROM 'acw' OR NEW.source IS DISTINCT FROM 'jrc_conversas'
    OR NOT (NEW.metadata ? 'qualification_id') THEN RETURN NEW; END IF;
  -- Do not acquire a late Account FOR UPDATE after an event's native FK check.
  -- Native pending creation already holds its account mutex; independent writes
  -- must retain the same uniqueness semantics and cannot mutate an old origin.
  INSERT INTO jrc_contact_center_ending_action_origins (account_id, origin_event_id)
    VALUES (NEW.account_id, NEW.id) ON CONFLICT (account_id, origin_event_id) DO NOTHING;
  RETURN NEW;
END $guard$;

CREATE TRIGGER cc_ending_action_pending_origin AFTER INSERT ON jrc_contact_center_agent_state_events
  FOR EACH ROW EXECUTE FUNCTION cc_ending_action_capture_pending();

-- Unapplied WIP. No migration loads this file and neither referenced owned table exists yet.
-- This seals immutable classification/source identity, never notes or answers.
-- Every execution must still validate native reason policy and form completion under the original actor.
-- Native AcwPolicy currently requires both reason and result; preserve that existing rule.

CREATE FUNCTION cc_ending_action_completion_document(origin_key bigint) RETURNS jsonb
LANGUAGE plpgsql STABLE AS $guard$
DECLARE origin jrc_contact_center_ending_action_origins%ROWTYPE;
  qualification jrc_contact_center_qualifications%ROWTYPE;
  form_key bigint;
BEGIN
  SELECT * INTO origin FROM jrc_contact_center_ending_action_origins WHERE id = origin_key;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT * INTO qualification FROM jrc_contact_center_qualifications
    WHERE id = origin.source_qualification_id AND account_id = origin.account_id
      AND account_user_id = origin.actor_account_user_id AND call_session_id = origin.call_session_id
      AND channel = 'voice' AND completed_at IS NOT NULL AND started_at IS NOT NULL;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT id INTO form_key FROM jrc_contact_center_qualification_forms
    WHERE account_id = origin.account_id AND qualification_id = qualification.id;
  RETURN jsonb_build_object('version', 1, 'origin_id', origin.id, 'account_id', origin.account_id,
    'source_qualification_id', qualification.id, 'call_session_id', origin.call_session_id,
    'actor_account_user_id', origin.actor_account_user_id, 'actor_user_id', origin.actor_user_id,
    'rule_version_id', origin.version_id, 'queue_scope_version_id', origin.queue_scope_version_id,
    'reason_code', qualification.reason_code, 'outcome_code', qualification.outcome_code,
    'started_at', qualification.started_at, 'completed_at', qualification.completed_at,
    'qualification_form_id', form_key);
END $guard$;

CREATE FUNCTION cc_ending_action_completion_guard() RETURNS trigger
LANGUAGE plpgsql AS $guard$
DECLARE origin jrc_contact_center_ending_action_origins%ROWTYPE;
  document jsonb;
BEGIN
  IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id) THEN RETURN OLD; END IF;
  IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'Ending action completion evidence is immutable'; END IF;
  IF NEW.source_qualification_id IS NOT NULL OR NEW.reason_code IS NOT NULL OR NEW.outcome_code IS NOT NULL
    OR NEW.completed_at IS NOT NULL OR NEW.integrity_sha256 IS NOT NULL
    OR NEW.private_completion_evidence IS DISTINCT FROM '{}'::jsonb THEN
    RAISE EXCEPTION 'Ending action completion provenance is server generated';
  END IF;
  SELECT * INTO origin FROM jrc_contact_center_ending_action_origins
    WHERE id = NEW.origin_id AND account_id = NEW.account_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ending action completion origin unavailable'; END IF;
  PERFORM 1 FROM jrc_contact_center_qualifications
    WHERE id = origin.source_qualification_id AND account_id = origin.account_id FOR UPDATE;
  document = cc_ending_action_completion_document(origin.id);
  IF document IS NULL OR COALESCE(btrim(document ->> 'reason_code'), '') = ''
    OR COALESCE(btrim(document ->> 'outcome_code'), '') = '' THEN
    RAISE EXCEPTION 'Ending action native completion unavailable';
  END IF;
  -- The configuration writer will require registered reasons for armed queues.
  -- Prove this exact historical catalogue, never a replacement current setting.
  IF NOT EXISTS (
    SELECT 1 FROM jrc_contact_center_ending_reason_versions catalog,
      LATERAL jsonb_array_elements(catalog.definition -> 'entries') reason
    WHERE catalog.id = origin.ending_reason_catalog_id AND catalog.account_id = origin.account_id
      AND reason ->> 'code' = document ->> 'reason_code' AND reason -> 'active' = 'true'::jsonb
      AND catalog.definition -> 'required_queue_ids' @> to_jsonb(ARRAY[origin.queue_id::text])
  ) THEN RAISE EXCEPTION 'Ending action original registered classification unavailable'; END IF;
  NEW.source_qualification_id = origin.source_qualification_id;
  NEW.reason_code = document ->> 'reason_code';
  NEW.outcome_code = document ->> 'outcome_code';
  NEW.completed_at = (document ->> 'completed_at')::timestamp;
  NEW.private_completion_evidence = document;
  NEW.created_at = timezone('UTC', clock_timestamp());
  NEW.integrity_sha256 = encode(sha256(convert_to(jsonb_build_object('account_id', NEW.account_id,
    'origin_id', NEW.origin_id, 'payload', NEW.private_completion_evidence, 'created_at', NEW.created_at)::text, 'UTF8')), 'hex');
  RETURN NEW;
END $guard$;

CREATE TRIGGER cc_ending_action_completion_immutable BEFORE INSERT OR UPDATE OR DELETE
  ON jrc_contact_center_ending_action_completions FOR EACH ROW EXECUTE FUNCTION cc_ending_action_completion_guard();

CREATE FUNCTION cc_ending_action_completion_matches(origin_key bigint, qualification_key bigint) RETURNS boolean
LANGUAGE sql STABLE AS $guard$
  SELECT EXISTS (
    SELECT 1 FROM jrc_contact_center_ending_action_completions completed
    WHERE completed.origin_id = origin_key AND completed.source_qualification_id = qualification_key
      AND completed.private_completion_evidence = cc_ending_action_completion_document(origin_key)
      AND completed.integrity_sha256 = encode(sha256(convert_to(jsonb_build_object('account_id', completed.account_id,
        'origin_id', completed.origin_id, 'payload', completed.private_completion_evidence, 'created_at', completed.created_at)::text, 'UTF8')), 'hex')
  )
$guard$;

-- Private unapplied source. Completing actual ACW records evidence only.
-- There is no enqueue, effect, grant or provider command in this trigger.

CREATE FUNCTION cc_ending_action_capture_completion() RETURNS trigger
LANGUAGE plpgsql AS $guard$
DECLARE origin_key bigint;
BEGIN
  IF OLD.completed_at IS NOT NULL OR NEW.completed_at IS NULL OR NEW.channel IS DISTINCT FROM 'voice' THEN RETURN NEW; END IF;
  SELECT id INTO origin_key FROM jrc_contact_center_ending_action_origins
    WHERE account_id = NEW.account_id AND source_qualification_id = NEW.id
      AND actor_account_user_id = NEW.account_user_id AND call_session_id = NEW.call_session_id;
  IF NOT FOUND THEN RETURN NEW; END IF;
  INSERT INTO jrc_contact_center_ending_action_completions (account_id, origin_id)
    VALUES (NEW.account_id, origin_key) ON CONFLICT (account_id, origin_id) DO NOTHING;
  RETURN NEW;
END $guard$;

CREATE TRIGGER cc_ending_action_native_completion AFTER UPDATE OF completed_at
  ON jrc_contact_center_qualifications FOR EACH ROW EXECUTE FUNCTION cc_ending_action_capture_completion();
