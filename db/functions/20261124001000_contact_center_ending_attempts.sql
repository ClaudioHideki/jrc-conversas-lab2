-- Internal technical history only. Neither function grants source/destination access.
CREATE FUNCTION cc_ending_attempt_guard() RETURNS trigger
LANGUAGE plpgsql AS $guard$
DECLARE origin jrc_contact_center_ending_action_origins%ROWTYPE;
  ready jrc_contact_center_ending_action_readinesses%ROWTYPE;
  version jrc_contact_center_ending_action_versions%ROWTYPE;
  rule jsonb;
BEGIN
  IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id) THEN RETURN OLD; END IF;
  IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'Ending attempts are immutable'; END IF;
  IF NEW.version_id IS NOT NULL OR NEW.actor_account_user_id IS NOT NULL OR NEW.actor_user_id IS NOT NULL
    OR NEW.created_at IS NOT NULL OR NEW.integrity_sha256 IS NOT NULL THEN
    RAISE EXCEPTION 'Ending attempt identity is server generated';
  END IF;
  PERFORM 1 FROM accounts WHERE id = NEW.account_id FOR NO KEY UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ending attempt account unavailable'; END IF;
  SELECT * INTO origin FROM jrc_contact_center_ending_action_origins WHERE id = NEW.origin_id AND account_id = NEW.account_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ending attempt original unavailable'; END IF;
  SELECT * INTO ready FROM jrc_contact_center_ending_action_readinesses WHERE id = NEW.readiness_id AND account_id = NEW.account_id;
  IF NOT FOUND OR ready.rule_code IS DISTINCT FROM NEW.rule_code OR NOT cc_ending_action_readiness_matches(ready.id, origin.id) THEN
    RAISE EXCEPTION 'Ending attempt prospective readiness unavailable';
  END IF;
  SELECT * INTO version FROM jrc_contact_center_ending_action_versions WHERE id = origin.version_id AND account_id = origin.account_id;
  SELECT entry INTO rule FROM jsonb_array_elements(version.private_definition -> 'entries') entry WHERE entry ->> 'code' = NEW.rule_code;
  IF rule IS NULL OR rule -> 'active' IS DISTINCT FROM 'true'::jsonb OR rule ->> 'execution_mode' IS DISTINCT FROM 'automatic' THEN
    RAISE EXCEPTION 'Explicit automatic ending rule required';
  END IF;
  IF NEW.destination_kind IS DISTINCT FROM 'project_task' OR NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(rule -> 'actions') entry WHERE entry ->> 'kind' = NEW.destination_kind
  ) THEN RAISE EXCEPTION 'Ending attempt destination unavailable'; END IF;
  IF EXISTS (SELECT 1 FROM jrc_contact_center_ending_action_versions later WHERE later.account_id = origin.account_id
    AND later.revision > version.revision AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(later.private_definition -> 'entries') entry
      WHERE entry ->> 'code' = NEW.rule_code AND entry -> 'active' = 'true'::jsonb)) THEN
    RAISE EXCEPTION 'Ending attempt permanently blocked by deactivation';
  END IF;
  NEW.version_id = origin.version_id;
  NEW.actor_account_user_id = origin.actor_account_user_id;
  NEW.actor_user_id = origin.actor_user_id;
  NEW.created_at = timezone('UTC', clock_timestamp());
  NEW.integrity_sha256 = encode(sha256(convert_to((to_jsonb(NEW) - 'integrity_sha256')::text, 'UTF8')), 'hex');
  RETURN NEW;
END $guard$;

CREATE FUNCTION cc_ending_attempt_outcome_guard() RETURNS trigger
LANGUAGE plpgsql AS $guard$
DECLARE attempt jrc_contact_center_ending_action_attempts%ROWTYPE;
  execution jrc_contact_center_ending_action_executions%ROWTYPE;
BEGIN
  IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id) THEN RETURN OLD; END IF;
  IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'Ending attempt outcomes are immutable'; END IF;
  IF NEW.created_at IS NOT NULL OR NEW.integrity_sha256 IS NOT NULL THEN
    RAISE EXCEPTION 'Ending attempt outcome time and digest are server generated';
  END IF;
  PERFORM 1 FROM accounts WHERE id = NEW.account_id FOR NO KEY UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ending attempt outcome account unavailable'; END IF;
  SELECT * INTO attempt FROM jrc_contact_center_ending_action_attempts WHERE id = NEW.attempt_id AND account_id = NEW.account_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ending attempt outcome original unavailable'; END IF;
  IF NEW.outcome = 'succeeded' THEN
    SELECT * INTO execution FROM jrc_contact_center_ending_action_executions WHERE id = NEW.execution_id AND account_id = NEW.account_id;
    IF NOT FOUND OR execution.origin_id IS DISTINCT FROM attempt.origin_id OR execution.rule_code IS DISTINCT FROM attempt.rule_code
      OR execution.readiness_id IS DISTINCT FROM attempt.readiness_id OR execution.destination_kind IS DISTINCT FROM attempt.destination_kind THEN
      RAISE EXCEPTION 'Ending attempt success identity mismatch';
    END IF;
  END IF;
  NEW.created_at = timezone('UTC', clock_timestamp());
  NEW.integrity_sha256 = encode(sha256(convert_to((to_jsonb(NEW) - 'integrity_sha256')::text, 'UTF8')), 'hex');
  RETURN NEW;
END $guard$;

CREATE TRIGGER cc_ending_attempt_immutable BEFORE INSERT OR UPDATE OR DELETE
  ON jrc_contact_center_ending_action_attempts FOR EACH ROW EXECUTE FUNCTION cc_ending_attempt_guard();
CREATE TRIGGER cc_ending_attempt_outcome_immutable BEFORE INSERT OR UPDATE OR DELETE
  ON jrc_contact_center_ending_action_attempt_outcomes FOR EACH ROW EXECUTE FUNCTION cc_ending_attempt_outcome_guard();
