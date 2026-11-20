# frozen_string_literal: true

# Immutable catalogue provenance and a first-observed call policy pin, separate from correctable operational timestamps.
class JrcContactCenter::EndingReasonCatalogSql
  VERSION_GUARD_SQL = <<~SQL.squish.freeze
    CREATE FUNCTION cc_ending_reason_version_guard() RETURNS trigger LANGUAGE plpgsql AS $guard$
    DECLARE source audits%ROWTYPE; last_revision integer; previous_definition jsonb;
    BEGIN
      IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id) THEN RETURN OLD; END IF;
      IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'Ending reason versions are immutable'; END IF;
      PERFORM 1 FROM accounts WHERE id = NEW.account_id FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'Ending reason account unavailable'; END IF;
      SELECT * INTO source FROM audits WHERE id = NEW.source_audit_id;
      IF NOT FOUND OR source.auditable_type IS DISTINCT FROM 'Account' OR source.auditable_id IS DISTINCT FROM NEW.account_id
        OR source.associated_type IS DISTINCT FROM 'Account' OR source.associated_id IS DISTINCT FROM NEW.account_id
        OR source.action IS DISTINCT FROM 'update' OR source.comment IS DISTINCT FROM 'jrc_contact_center_acw_policy_v1'
        OR source.audited_changes #> '{attributes,1,voice_reason_catalog}' IS DISTINCT FROM NEW.definition THEN
        RAISE EXCEPTION 'Ending reason audit provenance unavailable';
      END IF;
      SELECT revision, definition INTO last_revision, previous_definition
        FROM jrc_contact_center_ending_reason_versions WHERE account_id = NEW.account_id ORDER BY revision DESC LIMIT 1;
      IF NEW.revision <> COALESCE(last_revision, 0) + 1
        OR source.audited_changes #> '{attributes,0,voice_reason_catalog}' IS DISTINCT FROM previous_definition THEN
        RAISE EXCEPTION 'Ending reason revision sequence conflict';
      END IF;
      IF last_revision IS NOT NULL AND source.created_at < (SELECT MAX(created_at)
        FROM jrc_contact_center_ending_reason_versions WHERE account_id = NEW.account_id) THEN
        RAISE EXCEPTION 'Ending reason effective time conflict';
      END IF;
      NEW.created_at = source.created_at;
      NEW.actor_user_id = source.user_id;
      NEW.actor_user_type = source.user_type;
      NEW.integrity_sha256 = encode(sha256(convert_to(jsonb_build_object('account_id', NEW.account_id,
        'revision', NEW.revision, 'source_audit_id', NEW.source_audit_id, 'definition', NEW.definition)::text, 'UTF8')), 'hex');
      RETURN NEW;
    END $guard$;
    CREATE TRIGGER cc_ending_reason_version_guard BEFORE INSERT OR UPDATE OR DELETE
      ON jrc_contact_center_ending_reason_versions FOR EACH ROW EXECUTE FUNCTION cc_ending_reason_version_guard();
  SQL

  CALL_GUARD_SQL = <<~SQL.squish.freeze
    CREATE FUNCTION cc_ending_reason_call_guard() RETURNS trigger LANGUAGE plpgsql AS $guard$
    DECLARE configured jsonb; latest jsonb; selected_id bigint;
    BEGIN
      IF TG_OP = 'UPDATE' THEN
        IF NEW.ending_reason_version_id IS DISTINCT FROM OLD.ending_reason_version_id
          OR NEW.ending_reason_captured_started_at IS DISTINCT FROM OLD.ending_reason_captured_started_at
          OR (OLD.ending_reason_version_id IS NOT NULL AND NEW.account_id IS DISTINCT FROM OLD.account_id) THEN
          RAISE EXCEPTION 'Call ending reason origin is immutable';
        END IF;
        RETURN NEW;
      END IF;
      SELECT settings #> '{jrc_contact_center_acw,voice_reason_catalog}' INTO configured
        FROM accounts WHERE id = NEW.account_id FOR UPDATE;
      SELECT definition INTO latest FROM jrc_contact_center_ending_reason_versions
        WHERE account_id = NEW.account_id ORDER BY revision DESC LIMIT 1;
      IF configured IS DISTINCT FROM latest THEN RAISE EXCEPTION 'Ending reason ledger is not synchronized'; END IF;
      SELECT id INTO selected_id FROM jrc_contact_center_ending_reason_versions
        WHERE account_id = NEW.account_id AND created_at <= NEW.started_at ORDER BY created_at DESC, revision DESC LIMIT 1;
      IF NEW.ending_reason_version_id IS NOT NULL AND NEW.ending_reason_version_id IS DISTINCT FROM selected_id THEN
        RAISE EXCEPTION 'Call ending reason version cannot be supplied';
      END IF;
      IF NEW.ending_reason_captured_started_at IS NOT NULL AND (selected_id IS NULL
        OR NEW.ending_reason_captured_started_at IS DISTINCT FROM NEW.started_at) THEN
        RAISE EXCEPTION 'Call ending reason capture cannot be supplied';
      END IF;
      NEW.ending_reason_version_id = selected_id;
      NEW.ending_reason_captured_started_at = CASE WHEN selected_id IS NULL THEN NULL ELSE NEW.started_at END;
      RETURN NEW;
    END $guard$;
    CREATE TRIGGER cc_ending_reason_call_guard BEFORE INSERT OR UPDATE ON jrc_contact_center_call_sessions
      FOR EACH ROW EXECUTE FUNCTION cc_ending_reason_call_guard();
  SQL

  def version_guard
    VERSION_GUARD_SQL
  end

  def call_guard
    CALL_GUARD_SQL
  end
end
