-- Explicit, prospective execution readiness. Installation inserts nothing.
-- These metadata checks never replace current source/destination permissions.
CREATE FUNCTION cc_ending_action_readiness_guard() RETURNS trigger
LANGUAGE plpgsql AS $guard$
DECLARE version jrc_contact_center_ending_action_versions%ROWTYPE;
  member account_users%ROWTYPE;
  queue jrc_contact_center_queues%ROWTYPE;
  unit jrc_contact_center_units%ROWTYPE;
  scope jrc_contact_center_ending_action_queue_scopes%ROWTYPE;
  rule jsonb;
BEGIN
  IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id) THEN RETURN OLD; END IF;
  IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'Ending execution readiness is immutable'; END IF;
  IF NEW.actor_user_id IS NOT NULL OR NEW.rule_sha256 IS NOT NULL OR NEW.source_timezone IS NOT NULL
    OR NEW.cutoff_call_id IS NOT NULL OR NEW.cutoff_leg_id IS NOT NULL OR NEW.created_at IS NOT NULL THEN
    RAISE EXCEPTION 'Ending execution readiness evidence is server generated';
  END IF;
  -- Serialize with native configuration writers even for a direct database
  -- insert. This mutex is not a substitute for the caller's native policies.
  PERFORM 1 FROM accounts WHERE id = NEW.account_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ending readiness account unavailable'; END IF;
  SELECT * INTO version FROM jrc_contact_center_ending_action_versions
    WHERE id = NEW.version_id AND account_id = NEW.account_id;
  IF NOT FOUND OR version.revision IS DISTINCT FROM (SELECT max(revision)
    FROM jrc_contact_center_ending_action_versions WHERE account_id = NEW.account_id) THEN
    RAISE EXCEPTION 'Current ending rule version required';
  END IF;
  SELECT entry INTO rule FROM jsonb_array_elements(version.private_definition -> 'entries') entry
    WHERE entry ->> 'code' = NEW.rule_code;
  IF rule IS NULL OR rule -> 'active' IS DISTINCT FROM 'true'::jsonb
    OR rule ->> 'execution_mode' NOT IN ('automatic', 'agent_confirmation')
    OR rule ->> 'execution_mode' IS NULL THEN
    RAISE EXCEPTION 'Explicit active ending rule required';
  END IF;
  SELECT * INTO member FROM account_users WHERE id = NEW.actor_account_user_id AND account_id = NEW.account_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ending readiness actor unavailable'; END IF;
  SELECT * INTO queue FROM jrc_contact_center_queues WHERE id::text = rule ->> 'queue_id' AND account_id = NEW.account_id;
  IF NOT FOUND OR queue.status IS DISTINCT FROM 'active' THEN RAISE EXCEPTION 'Ending readiness source unavailable'; END IF;
  SELECT * INTO unit FROM jrc_contact_center_units WHERE id = queue.unit_id AND account_id = NEW.account_id;
  IF NOT FOUND OR unit.status IS DISTINCT FROM 'active' THEN RAISE EXCEPTION 'Ending readiness source unavailable'; END IF;
  SELECT * INTO scope FROM jrc_contact_center_ending_action_queue_scopes
    WHERE source_queue_id = queue.id AND account_id = NEW.account_id ORDER BY revision DESC LIMIT 1;
  IF NOT FOUND OR scope.scope_state IS DISTINCT FROM 'mapped' OR scope.unit_id IS DISTINCT FROM unit.id
    OR rule #>> '{scope,queue_scope_version_id}' IS DISTINCT FROM scope.id::text
    OR rule #>> '{scope,integrity_sha256}' IS DISTINCT FROM scope.integrity_sha256 THEN
    RAISE EXCEPTION 'Ending readiness source scope changed';
  END IF;
  NEW.actor_user_id = member.user_id;
  NEW.rule_sha256 = encode(sha256(convert_to(rule::text, 'UTF8')), 'hex');
  NEW.source_timezone = unit.timezone;
  -- Sequence high-water marks include allocated but uncommitted IDs. MAX also
  -- covers explicit imported IDs. Conservative cached IDs may be excluded;
  -- no previously observed call/leg may become eligible retrospectively.
  NEW.cutoff_call_id = greatest(coalesce(pg_sequence_last_value(pg_get_serial_sequence('jrc_contact_center_call_sessions', 'id')::regclass), 0),
    coalesce((SELECT max(id) FROM jrc_contact_center_call_sessions), 0));
  NEW.cutoff_leg_id = greatest(coalesce(pg_sequence_last_value(pg_get_serial_sequence('jrc_contact_center_call_legs', 'id')::regclass), 0),
    coalesce((SELECT max(id) FROM jrc_contact_center_call_legs), 0));
  NEW.created_at = timezone('UTC', clock_timestamp());
  RETURN NEW;
END $guard$;

CREATE TRIGGER cc_ending_action_readiness_immutable BEFORE INSERT OR UPDATE OR DELETE
  ON jrc_contact_center_ending_action_readinesses FOR EACH ROW EXECUTE FUNCTION cc_ending_action_readiness_guard();

-- Prospective metadata admission only; callers must still reauthorize the
-- original actor and every destination and apply permanent disable barriers.
CREATE FUNCTION cc_ending_action_readiness_matches(readiness_id bigint, origin_id bigint) RETURNS boolean
LANGUAGE sql STABLE AS $match$
  SELECT EXISTS (
    SELECT 1 FROM jrc_contact_center_ending_action_readinesses ready
    JOIN jrc_contact_center_ending_action_origins origin ON origin.id = origin_id AND origin.account_id = ready.account_id
    JOIN jrc_contact_center_ending_action_versions activation ON activation.id = ready.version_id AND activation.account_id = ready.account_id
    JOIN jrc_contact_center_ending_action_versions pinned ON pinned.id = origin.version_id AND pinned.account_id = ready.account_id
    JOIN jrc_contact_center_units unit ON unit.id = origin.unit_id AND unit.account_id = ready.account_id
    CROSS JOIN LATERAL jsonb_array_elements(activation.private_definition -> 'entries') activated
    WHERE ready.id = readiness_id AND activated ->> 'code' = ready.rule_code
      AND unit.timezone = ready.source_timezone AND origin.call_session_id > ready.cutoff_call_id
      AND origin.call_leg_id > ready.cutoff_leg_id AND origin.created_at >= ready.created_at
      AND (origin.private_origin_evidence ->> 'captured_call_started_at')::timestamp >= ready.created_at
      AND activation.revision <= pinned.revision
      AND NOT EXISTS (
        SELECT 1 FROM jrc_contact_center_ending_action_versions intermediate
        WHERE intermediate.account_id = ready.account_id AND intermediate.revision BETWEEN activation.revision AND pinned.revision
          AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(intermediate.private_definition -> 'entries') entry
            WHERE entry ->> 'code' = ready.rule_code AND entry = activated)
      )
  );
$match$;
