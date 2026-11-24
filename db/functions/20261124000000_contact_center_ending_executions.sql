-- PRIVATE CANDIDATE. No caller-supplied actor, version, trigger or timestamp.
-- A receipt records a native success; it does not grant any module permission.
CREATE FUNCTION cc_ending_execution_guard() RETURNS trigger
LANGUAGE plpgsql AS $guard$
DECLARE origin jrc_contact_center_ending_action_origins%ROWTYPE;
  version jrc_contact_center_ending_action_versions%ROWTYPE;
  ready jrc_contact_center_ending_action_readinesses%ROWTYPE;
  rule jsonb;
  action jsonb;
  confirmation jrc_contact_center_ending_reason_confirmations%ROWTYPE;
  completion jrc_contact_center_ending_action_completions%ROWTYPE;
  target jrc_projects_tasks%ROWTYPE;
BEGIN
  IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id) THEN RETURN OLD; END IF;
  IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'Ending destination successes are immutable'; END IF;
  IF NEW.version_id IS NOT NULL OR NEW.actor_account_user_id IS NOT NULL OR NEW.actor_user_id IS NOT NULL
    OR NEW.trigger_kind IS NOT NULL OR NEW.trigger_id IS NOT NULL OR NEW.triggered_at IS NOT NULL
    OR NEW.created_at IS NOT NULL OR NEW.integrity_sha256 IS NOT NULL THEN
    RAISE EXCEPTION 'Ending destination success evidence is server generated';
  END IF;
  PERFORM 1 FROM accounts WHERE id = NEW.account_id FOR NO KEY UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ending execution account unavailable'; END IF;
  SELECT * INTO origin FROM jrc_contact_center_ending_action_origins WHERE id = NEW.origin_id AND account_id = NEW.account_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ending execution original source unavailable'; END IF;
  SELECT * INTO ready FROM jrc_contact_center_ending_action_readinesses WHERE id = NEW.readiness_id AND account_id = NEW.account_id;
  IF NOT FOUND OR NOT cc_ending_action_readiness_matches(ready.id, origin.id) THEN
    RAISE EXCEPTION 'Ending execution prospective readiness unavailable';
  END IF;
  IF ready.rule_code IS DISTINCT FROM NEW.rule_code THEN RAISE EXCEPTION 'Ending execution readiness rule mismatch'; END IF;
  SELECT * INTO version FROM jrc_contact_center_ending_action_versions WHERE id = origin.version_id AND account_id = origin.account_id;
  SELECT entry INTO rule FROM jsonb_array_elements(version.private_definition -> 'entries') entry WHERE entry ->> 'code' = NEW.rule_code;
  IF rule IS NULL OR rule -> 'active' IS DISTINCT FROM 'true'::jsonb OR rule ->> 'execution_mode' IS DISTINCT FROM 'automatic' THEN
    RAISE EXCEPTION 'Explicit automatic ending rule required';
  END IF;
  IF EXISTS (SELECT 1 FROM jrc_contact_center_ending_action_versions later WHERE later.account_id = origin.account_id
    AND later.revision > version.revision AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(later.private_definition -> 'entries') entry
      WHERE entry ->> 'code' = NEW.rule_code AND entry -> 'active' = 'true'::jsonb)) THEN
    RAISE EXCEPTION 'Ending execution permanently blocked by deactivation';
  END IF;
  SELECT entry INTO action FROM jsonb_array_elements(rule -> 'actions') entry WHERE entry ->> 'kind' = NEW.destination_kind;
  IF action IS NULL OR NEW.destination_kind IS DISTINCT FROM 'project_task' THEN RAISE EXCEPTION 'Ending destination unavailable'; END IF;
  SELECT * INTO target FROM jrc_projects_tasks WHERE id = NEW.target_id AND account_id = origin.account_id
    AND project_id::text = action #>> '{parameters,project_id}' AND created_by_id = origin.actor_user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ending native destination identity mismatch'; END IF;

  IF rule ->> 'timing' = 'call_end' THEN
    SELECT * INTO confirmation FROM jrc_contact_center_ending_reason_confirmations
      WHERE account_id = origin.account_id AND source_qualification_id = origin.source_qualification_id
        AND actor_account_user_id = origin.actor_account_user_id AND actor_user_id = origin.actor_user_id
        AND catalogue_id = origin.ending_reason_catalog_id AND reason_code = rule ->> 'reason_code';
    IF NOT FOUND THEN RAISE EXCEPTION 'Ending classification must be explicitly confirmed'; END IF;
    NEW.trigger_kind = 'ending_reason_confirmation';
    NEW.trigger_id = confirmation.id;
    NEW.triggered_at = greatest(origin.created_at, confirmation.created_at);
  ELSIF rule ->> 'timing' = 'acw_completed' THEN
    SELECT * INTO completion FROM jrc_contact_center_ending_action_completions
      WHERE account_id = origin.account_id AND origin_id = origin.id AND reason_code = rule ->> 'reason_code';
    IF NOT FOUND OR NOT cc_ending_action_completion_matches(origin.id, origin.source_qualification_id) THEN
      RAISE EXCEPTION 'Actual native ACW completion required';
    END IF;
    IF jsonb_array_length(rule #> '{conditions,outcome_codes}') > 0
      AND NOT ((rule #> '{conditions,outcome_codes}') ? completion.outcome_code) THEN
      RAISE EXCEPTION 'Ending completion condition mismatch';
    END IF;
    NEW.trigger_kind = 'ending_action_completion';
    NEW.trigger_id = completion.id;
    NEW.triggered_at = completion.completed_at;
  ELSE RAISE EXCEPTION 'Ending execution trigger unavailable';
  END IF;
  NEW.version_id = origin.version_id;
  NEW.actor_account_user_id = origin.actor_account_user_id;
  NEW.actor_user_id = origin.actor_user_id;
  NEW.created_at = timezone('UTC', clock_timestamp());
  NEW.integrity_sha256 = encode(sha256(convert_to((to_jsonb(NEW) - 'integrity_sha256')::text, 'UTF8')), 'hex');
  RETURN NEW;
END $guard$;

CREATE TRIGGER cc_ending_execution_immutable BEFORE INSERT OR UPDATE OR DELETE
  ON jrc_contact_center_ending_action_executions FOR EACH ROW EXECUTE FUNCTION cc_ending_execution_guard();
