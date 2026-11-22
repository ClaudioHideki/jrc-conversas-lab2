-- Additive classification evidence only. Existing catalogue, ACW and pause functions remain unchanged.
CREATE FUNCTION cc_ending_confirmation_guard() RETURNS trigger LANGUAGE plpgsql AS $guard$
DECLARE qualification jrc_contact_center_qualifications%ROWTYPE;
  membership account_users%ROWTYPE;
  source_event jrc_contact_center_agent_state_events%ROWTYPE;
  catalogue jrc_contact_center_ending_reason_versions%ROWTYPE;
  capture jsonb;
  label text;
BEGIN
  IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id) THEN
    RETURN OLD;
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.qualification_id IS NULL AND OLD.qualification_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM jrc_contact_center_qualifications WHERE id = OLD.qualification_id)
    AND (to_jsonb(NEW) - 'qualification_id') = (to_jsonb(OLD) - 'qualification_id') THEN
    RETURN NEW;
  END IF;
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'Ending reason confirmation is immutable';
  END IF;
  IF NEW.actor_account_user_id IS NOT NULL OR NEW.actor_user_id IS NOT NULL OR NEW.catalogue_id IS NOT NULL
    OR NEW.reason_label IS NOT NULL OR NEW.integrity_sha256 IS NOT NULL OR NEW.payload <> '{}'::jsonb THEN
    RAISE EXCEPTION 'Ending reason confirmation provenance is server generated';
  END IF;
  SELECT * INTO qualification FROM jrc_contact_center_qualifications
    WHERE id = NEW.qualification_id AND account_id = NEW.account_id FOR UPDATE;
  IF NOT FOUND OR qualification.completed_at IS NOT NULL OR qualification.started_at IS NULL
    OR qualification.channel <> 'voice' OR qualification.reason_code IS DISTINCT FROM NEW.reason_code
    OR (NEW.source_qualification_id IS NOT NULL AND NEW.source_qualification_id <> qualification.id) THEN
    RAISE EXCEPTION 'Ending reason pending qualification unavailable';
  END IF;
  SELECT * INTO membership FROM account_users
    WHERE id = qualification.account_user_id AND account_id = NEW.account_id FOR KEY SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Ending reason original actor unavailable'; END IF;
  SELECT * INTO source_event FROM jrc_contact_center_agent_state_events
    WHERE account_id = NEW.account_id AND account_user_id = membership.id AND source = 'jrc_conversas'
      AND state = 'acw' AND external_event_id = 'qualification:' || qualification.id::text || ':pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'Ending reason native origin unavailable'; END IF;
  capture = source_event.metadata -> 'ending_reason_snapshot_v1';
  IF capture IS NULL OR capture ->> 'qualification_id' IS DISTINCT FROM qualification.id::text
    OR capture ->> 'account_id' IS DISTINCT FROM NEW.account_id::text
    OR capture ->> 'account_user_id' IS DISTINCT FROM membership.id::text
    OR capture ->> 'call_session_id' IS DISTINCT FROM qualification.call_session_id::text THEN
    RAISE EXCEPTION 'Ending reason native origin mismatch';
  END IF;
  SELECT * INTO catalogue FROM jrc_contact_center_ending_reason_versions
    WHERE id::text = capture ->> 'catalogue_id' AND account_id = NEW.account_id
      AND integrity_sha256 = capture ->> 'integrity_sha256';
  IF NOT FOUND THEN RAISE EXCEPTION 'Ending reason frozen catalogue unavailable'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM jrc_contact_center_call_sessions session JOIN jrc_contact_center_call_legs leg
      ON leg.call_session_id = session.id AND leg.account_id = session.account_id
    WHERE session.id = qualification.call_session_id AND session.account_id = NEW.account_id
      AND session.ending_reason_version_id = catalogue.id AND leg.id::text = capture ->> 'call_leg_id'
      AND leg.account_user_id = membership.id AND leg.answered_at IS NOT NULL
      AND (session.status IN ('ended', 'failed') OR leg.status IN ('ended', 'failed', 'transferred'))
  ) THEN RAISE EXCEPTION 'Ending reason attended call has not ended'; END IF;
  SELECT entry ->> 'name' INTO label FROM jsonb_array_elements(catalogue.definition -> 'entries') entry
    WHERE entry ->> 'code' = NEW.reason_code AND entry -> 'active' = 'true'::jsonb;
  IF label IS NULL THEN RAISE EXCEPTION 'Registered ending reason required'; END IF;
  NEW.source_qualification_id = qualification.id;
  NEW.actor_account_user_id = membership.id;
  NEW.actor_user_id = membership.user_id;
  NEW.catalogue_id = catalogue.id;
  NEW.reason_label = label;
  NEW.created_at = timezone('UTC', statement_timestamp());
  NEW.payload = jsonb_build_object('version', 1, 'origin', capture, 'source_event_id', source_event.id,
    'actor_user_id', membership.user_id, 'reason_code', NEW.reason_code, 'reason_label', label,
    'catalogue_revision', catalogue.revision, 'confirms_classification_only', true);
  NEW.integrity_sha256 = encode(sha256(convert_to(jsonb_build_object('account_id', NEW.account_id,
    'source_qualification_id', NEW.source_qualification_id, 'request_key', NEW.request_key,
    'input_digest', NEW.input_digest, 'payload', NEW.payload, 'created_at', NEW.created_at)::text, 'UTF8')), 'hex');
  RETURN NEW;
END $guard$;

CREATE TRIGGER cc_ending_confirmation_immutable BEFORE INSERT OR UPDATE OR DELETE
  ON jrc_contact_center_ending_reason_confirmations FOR EACH ROW EXECUTE FUNCTION cc_ending_confirmation_guard();

CREATE FUNCTION cc_ending_confirmation_qualification_guard() RETURNS trigger LANGUAGE plpgsql AS $guard$
BEGIN
  IF NEW.reason_code IS DISTINCT FROM OLD.reason_code AND EXISTS (
    SELECT 1 FROM jrc_contact_center_ending_reason_confirmations
      WHERE account_id = OLD.account_id AND source_qualification_id = OLD.id
  ) THEN RAISE EXCEPTION 'Confirmed ending reason cannot be changed'; END IF;
  RETURN NEW;
END $guard$;

CREATE TRIGGER cc_ending_confirmation_fixed_reason BEFORE UPDATE ON jrc_contact_center_qualifications
  FOR EACH ROW EXECUTE FUNCTION cc_ending_confirmation_qualification_guard();
