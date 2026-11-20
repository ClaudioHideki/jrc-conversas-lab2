# frozen_string_literal: true

# Native ACW origin and qualification guards, also retained by the existing PostgreSQL schema dumper.
class JrcContactCenter::EndingReasonOriginSql
  def call
    ORIGIN_SQL + QUALIFICATION_SQL
  end

  ORIGIN_SQL = <<~SQL.squish.freeze
    CREATE FUNCTION cc_ending_reason_origin_guard() RETURNS trigger LANGUAGE plpgsql AS $guard$
    DECLARE qualification jrc_contact_center_qualifications%ROWTYPE;
      session jrc_contact_center_call_sessions%ROWTYPE; version jrc_contact_center_ending_reason_versions%ROWTYPE;
      leg jrc_contact_center_call_legs%ROWTYPE; queue_id bigint; unit_id bigint; snapshot jsonb;
    BEGIN
      IF TG_OP = 'DELETE' THEN
        IF OLD.metadata ? 'ending_reason_snapshot_v1' AND EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id)
          AND EXISTS (SELECT 1 FROM account_users WHERE id = OLD.account_user_id)
          AND EXISTS (SELECT 1 FROM jrc_contact_center_qualifications WHERE id::text = OLD.metadata ->> 'qualification_id') THEN
          RAISE EXCEPTION 'Ending reason original evidence cannot be deleted';
        END IF;
        RETURN OLD;
      END IF;
      IF TG_OP = 'UPDATE' THEN
        IF NEW.metadata -> 'ending_reason_snapshot_v1' IS DISTINCT FROM OLD.metadata -> 'ending_reason_snapshot_v1'
          OR (OLD.metadata ? 'ending_reason_snapshot_v1' AND
            (NEW.account_id, NEW.account_user_id, NEW.source, NEW.external_event_id, NEW.state, NEW.started_at,
             NEW.metadata -> 'qualification_id') IS DISTINCT FROM
            (OLD.account_id, OLD.account_user_id, OLD.source, OLD.external_event_id, OLD.state, OLD.started_at,
             OLD.metadata -> 'qualification_id')) THEN RAISE EXCEPTION 'Ending reason original evidence is immutable'; END IF;
        RETURN NEW;
      END IF;
      IF NEW.metadata ? 'ending_reason_snapshot_v1' THEN RAISE EXCEPTION 'Ending reason origin is server generated'; END IF;
      IF NEW.state IS DISTINCT FROM 'acw' OR NEW.source IS DISTINCT FROM 'jrc_conversas' OR NOT (NEW.metadata ? 'qualification_id') THEN RETURN NEW; END IF;
      SELECT * INTO qualification FROM jrc_contact_center_qualifications
        WHERE id::text = NEW.metadata ->> 'qualification_id' AND account_id = NEW.account_id AND account_user_id = NEW.account_user_id;
      IF NOT FOUND OR NEW.external_event_id IS DISTINCT FROM 'qualification:' || qualification.id::text || ':pending' THEN RETURN NEW; END IF;
      SELECT * INTO session FROM jrc_contact_center_call_sessions WHERE id = qualification.call_session_id AND account_id = NEW.account_id;
      IF NOT FOUND OR session.ending_reason_version_id IS NULL THEN RETURN NEW; END IF;
      SELECT * INTO version FROM jrc_contact_center_ending_reason_versions
        WHERE id = session.ending_reason_version_id AND account_id = NEW.account_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'Ending reason frozen version unavailable'; END IF;
      SELECT * INTO leg FROM jrc_contact_center_call_legs WHERE call_session_id = session.id
        AND account_id = NEW.account_id AND account_user_id = NEW.account_user_id AND answered_at IS NOT NULL ORDER BY id DESC LIMIT 1;
      IF NOT FOUND THEN RAISE EXCEPTION 'Ending reason answered leg unavailable'; END IF;
      queue_id = COALESCE(leg.queue_id, session.current_queue_id);
      SELECT queues.unit_id INTO unit_id FROM jrc_contact_center_queues queues WHERE queues.id = queue_id AND account_id = NEW.account_id;
      snapshot = jsonb_build_object('version', 1, 'qualification_id', qualification.id, 'account_id', NEW.account_id,
        'account_user_id', NEW.account_user_id, 'call_session_id', session.id, 'call_leg_id', leg.id,
        'catalogue_id', version.id, 'integrity_sha256', version.integrity_sha256, 'queue_id', queue_id,
        'unit_id', COALESCE(unit_id, session.current_unit_id),
        'required', COALESCE(version.definition -> 'required_queue_ids', '[]'::jsonb) @> to_jsonb(ARRAY[queue_id::text]));
      NEW.metadata = NEW.metadata || jsonb_build_object('ending_reason_snapshot_v1', snapshot);
      RETURN NEW;
    END $guard$;
    CREATE TRIGGER cc_ending_reason_origin_guard BEFORE INSERT OR UPDATE OR DELETE ON jrc_contact_center_agent_state_events
      FOR EACH ROW EXECUTE FUNCTION cc_ending_reason_origin_guard();
  SQL

  QUALIFICATION_SQL = <<~SQL.squish.freeze
    CREATE FUNCTION cc_ending_reason_qualification_guard() RETURNS trigger LANGUAGE plpgsql AS $guard$
    DECLARE snapshot jsonb; definition jsonb;
    BEGIN
      IF TG_OP = 'UPDATE' AND EXISTS (SELECT 1 FROM jrc_contact_center_call_sessions
        WHERE id = OLD.call_session_id AND ending_reason_version_id IS NOT NULL) AND
        (NEW.account_id, NEW.account_user_id, NEW.call_session_id, NEW.started_at) IS DISTINCT FROM
        (OLD.account_id, OLD.account_user_id, OLD.call_session_id, OLD.started_at) THEN
        RAISE EXCEPTION 'Ending reason qualification identity is immutable';
      END IF;
      IF NOT EXISTS (SELECT 1 FROM jrc_contact_center_call_sessions WHERE id = NEW.call_session_id
        AND account_id = NEW.account_id AND ending_reason_version_id IS NOT NULL) THEN RETURN NEW; END IF;
      IF TG_OP = 'UPDATE' AND OLD.completed_at IS NOT NULL AND
        (NEW.reason_code, NEW.outcome_code, NEW.notes, NEW.completed_at, NEW.duration_seconds, NEW.acw_limit_seconds) IS DISTINCT FROM
        (OLD.reason_code, OLD.outcome_code, OLD.notes, OLD.completed_at, OLD.duration_seconds, OLD.acw_limit_seconds) THEN
        RAISE EXCEPTION 'Completed ending reason classification is immutable';
      END IF;
      IF COALESCE(btrim(NEW.reason_code), '') = '' AND NEW.completed_at IS NULL THEN RETURN NEW; END IF;
      SELECT metadata -> 'ending_reason_snapshot_v1' INTO snapshot FROM jrc_contact_center_agent_state_events
        WHERE account_id = NEW.account_id AND account_user_id = NEW.account_user_id AND state = 'acw'
        AND source = 'jrc_conversas' AND external_event_id = 'qualification:' || NEW.id::text || ':pending';
      IF snapshot IS NULL THEN RAISE EXCEPTION 'Ending reason origin unavailable'; END IF;
      IF (snapshot ->> 'required')::boolean THEN
        SELECT versions.definition INTO definition FROM jrc_contact_center_ending_reason_versions versions
          WHERE id::text = snapshot ->> 'catalogue_id' AND account_id = NEW.account_id;
        IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(definition -> 'entries') entry
          WHERE entry ->> 'code' = NEW.reason_code AND entry -> 'active' = 'true'::jsonb) THEN
          RAISE EXCEPTION 'Registered ending reason required';
        END IF;
      END IF;
      RETURN NEW;
    END $guard$;
    CREATE TRIGGER cc_ending_reason_qualification_guard BEFORE INSERT OR UPDATE ON jrc_contact_center_qualifications
      FOR EACH ROW EXECUTE FUNCTION cc_ending_reason_qualification_guard();
  SQL
end
