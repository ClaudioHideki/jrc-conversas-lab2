-- Internal human revisions only. No provider update, grant, backfill, command or recommendation execution.
CREATE FUNCTION cc_quality_review_append() RETURNS trigger LANGUAGE plpgsql AS $append$
DECLARE source_call jrc_contact_center_call_sessions%ROWTYPE;
  source_record telephony_call_records%ROWTYPE;
  previous_revision integer;
BEGIN
  -- Same native Account mutex as profile/coverage changes and the authenticated writer.
  PERFORM 1 FROM accounts WHERE id = NEW.account_id FOR NO KEY UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Quality review account unavailable'; END IF;
  SELECT * INTO source_record FROM telephony_call_records WHERE id = NEW.recording_id AND account_id = NEW.account_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Quality review recording unavailable'; END IF;
  SELECT * INTO source_call FROM jrc_contact_center_call_sessions WHERE id = NEW.call_session_id AND account_id = NEW.account_id;
  IF NOT FOUND OR source_call.external_session_id IS DISTINCT FROM source_record.external_unique_id
    OR source_call.provider IS DISTINCT FROM source_record.provider THEN
    RAISE EXCEPTION 'Quality review exact native origin required';
  END IF;
  IF NEW.original_analysis ->> 'call_id' IS DISTINCT FROM source_record.external_unique_id THEN
    RAISE EXCEPTION 'Quality review captured analysis origin mismatch';
  END IF;
  IF NEW.scope_snapshot ->> 'account_id' IS DISTINCT FROM NEW.account_id::text
    OR NEW.scope_snapshot ->> 'unit_id' IS DISTINCT FROM source_call.current_unit_id::text
    OR NEW.scope_snapshot ->> 'queue_id' IS DISTINCT FROM source_call.current_queue_id::text THEN
    RAISE EXCEPTION 'Quality review native scope snapshot mismatch';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM account_users WHERE id = NEW.actor_account_user_id
    AND account_id = NEW.account_id AND user_id = NEW.actor_user_id) THEN
    RAISE EXCEPTION 'Quality review native actor required';
  END IF;
  SELECT COALESCE(max(revision), 0) INTO previous_revision FROM jrc_contact_center_quality_review_revisions
    WHERE account_id = NEW.account_id AND recording_id = NEW.recording_id;
  IF NEW.revision <> previous_revision + 1 THEN RAISE EXCEPTION 'Quality review revision conflict'; END IF;
  RETURN NEW;
END;
$append$;

CREATE FUNCTION cc_quality_review_immutable() RETURNS trigger LANGUAGE plpgsql AS $immutable$
BEGIN
  -- Existing account deletion remains possible. Deleting a call, actor or an individual revision cannot erase this history.
  IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id) THEN RETURN OLD; END IF;
  RAISE EXCEPTION 'Quality review history is immutable';
END;
$immutable$;

CREATE TRIGGER cc_quality_review_append_guard BEFORE INSERT ON jrc_contact_center_quality_review_revisions
  FOR EACH ROW EXECUTE FUNCTION cc_quality_review_append();
CREATE TRIGGER cc_quality_review_immutable_guard BEFORE UPDATE OR DELETE ON jrc_contact_center_quality_review_revisions
  FOR EACH ROW EXECUTE FUNCTION cc_quality_review_immutable();
