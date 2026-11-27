-- Historical link receipt only. Tasks, state and permissions remain native Projects data.
CREATE FUNCTION cc_recording_task_append() RETURNS trigger LANGUAGE plpgsql AS $append$
DECLARE source_call jrc_contact_center_call_sessions%ROWTYPE;
  source_record telephony_call_records%ROWTYPE;
  source_unit jrc_contact_center_units%ROWTYPE;
BEGIN
  PERFORM 1 FROM accounts WHERE id = NEW.account_id FOR NO KEY UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Recording task account unavailable'; END IF;
  SELECT * INTO source_record FROM telephony_call_records WHERE id = NEW.recording_id AND account_id = NEW.account_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Recording task source unavailable'; END IF;
  SELECT * INTO source_call FROM jrc_contact_center_call_sessions WHERE id = NEW.call_session_id AND account_id = NEW.account_id;
  IF NOT FOUND OR source_call.external_session_id IS DISTINCT FROM source_record.external_unique_id
    OR source_call.provider IS DISTINCT FROM source_record.provider THEN
    RAISE EXCEPTION 'Recording task exact native origin required';
  END IF;
  SELECT * INTO source_unit FROM jrc_contact_center_units
    WHERE id = source_call.current_unit_id AND account_id = NEW.account_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Recording task current native unit required'; END IF;
  IF NEW.scope_snapshot ->> 'issuer_company_id' IS DISTINCT FROM source_unit.settings ->> 'issuer_company_id'
    OR NEW.scope_snapshot ->> 'business_unit_id' IS DISTINCT FROM source_unit.settings ->> 'business_unit_id' THEN
    RAISE EXCEPTION 'Recording task native corporate scope mismatch';
  END IF;
  IF NEW.scope_snapshot ->> 'account_id' IS DISTINCT FROM NEW.account_id::text
    OR source_call.current_unit_id IS NULL
    OR NEW.scope_snapshot ->> 'unit_id' IS DISTINCT FROM source_call.current_unit_id::text
    OR NEW.scope_snapshot ->> 'queue_id' IS DISTINCT FROM source_call.current_queue_id::text THEN
    RAISE EXCEPTION 'Recording task native scope snapshot mismatch';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM account_users WHERE id = NEW.actor_account_user_id
    AND account_id = NEW.account_id AND user_id = NEW.created_by_id) THEN
    RAISE EXCEPTION 'Recording task native actor required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM jrc_projects_tasks t JOIN jrc_projects_projects p ON p.id = t.project_id
    WHERE t.id = NEW.task_id AND t.account_id = NEW.account_id AND p.account_id = NEW.account_id
      AND p.id = NEW.project_id) THEN
    RAISE EXCEPTION 'Recording task exact native target required';
  END IF;
  RETURN NEW;
END;
$append$;

CREATE FUNCTION cc_recording_task_immutable() RETURNS trigger LANGUAGE plpgsql AS $immutable$
BEGIN
  -- Preserve source/actor/task deletion semantics and history. Only Account's native cascade removes receipts.
  IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id) THEN RETURN OLD; END IF;
  RAISE EXCEPTION 'Recording task history is immutable';
END;
$immutable$;

CREATE TRIGGER cc_recording_task_append_guard BEFORE INSERT ON jrc_contact_center_recording_task_links
  FOR EACH ROW EXECUTE FUNCTION cc_recording_task_append();
CREATE TRIGGER cc_recording_task_immutable_guard BEFORE UPDATE OR DELETE ON jrc_contact_center_recording_task_links
  FOR EACH ROW EXECUTE FUNCTION cc_recording_task_immutable();
