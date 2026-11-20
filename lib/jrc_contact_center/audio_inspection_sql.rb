# frozen_string_literal: true

# Separate append-only inspection domain; does not replace historical file or storage guards.
class JrcContactCenter::AudioInspectionSql
  SQL = <<~SQL.squish.freeze
    CREATE FUNCTION cc_institutional_audio_inspection_guard() RETURNS trigger LANGUAGE plpgsql AS $guard$
    DECLARE source jrc_contact_center_audio_versions%ROWTYPE; previous_attempt integer; document jsonb;
    BEGIN
      IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'Institutional audio observations are immutable'; END IF;
      PERFORM 1 FROM accounts WHERE id = NEW.account_id FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'Institutional audio inspection account unavailable'; END IF;
      SELECT * INTO source FROM jrc_contact_center_audio_versions
        WHERE id = NEW.audio_version_id AND account_id = NEW.account_id AND unit_id = NEW.unit_id FOR UPDATE;
      IF NOT FOUND OR source.blob_id IS DISTINCT FROM NEW.source_blob_id OR source.sha256 IS DISTINCT FROM NEW.expected_sha256 THEN
        RAISE EXCEPTION 'Institutional audio inspection origin unavailable';
      END IF;
      IF NOT EXISTS (SELECT 1 FROM account_users WHERE account_id = NEW.account_id AND user_id = NEW.created_by_id) THEN
        RAISE EXCEPTION 'Institutional audio inspection actor unavailable';
      END IF;
      SELECT MAX(attempt) INTO previous_attempt FROM jrc_contact_center_audio_inspections
        WHERE audio_version_id = NEW.audio_version_id;
      IF NEW.attempt <> COALESCE(previous_attempt, 0) + 1 THEN
        RAISE EXCEPTION 'Institutional audio observation sequence conflict';
      END IF;
      IF NEW.probe_state <> 'valid' THEN RETURN NEW; END IF;
      document := NEW.metadata;
      IF (jsonb_typeof(document) = 'object' AND document ?& ARRAY[
          'container', 'codec', 'content_type', 'duration_ms', 'sample_rate', 'channels', 'probe_version']
        AND document - ARRAY['container', 'codec', 'content_type', 'duration_ms', 'sample_rate', 'channels', 'probe_version'] = '{}'::jsonb
        AND octet_length(document::text) <= 4096
        AND jsonb_typeof(document -> 'codec') = 'string' AND length(document ->> 'codec') BETWEEN 1 AND 200
        AND jsonb_typeof(document -> 'probe_version') = 'string'
        AND length(document ->> 'probe_version') BETWEEN 1 AND 200 AND document ->> 'probe_version' LIKE 'ffprobe version %'
        AND NEW.decoder_version IS NOT NULL AND NEW.decoder_version LIKE 'ffmpeg version %'
        AND jsonb_typeof(document -> 'content_type') = 'string' AND document ->> 'content_type' = source.content_type
        AND jsonb_typeof(document -> 'container') = 'string'
        AND CASE document ->> 'container'
          WHEN 'wav' THEN document ->> 'content_type' = 'audio/wav'
          WHEN 'mp3' THEN document ->> 'content_type' = 'audio/mpeg'
          WHEN 'ogg' THEN document ->> 'content_type' = 'audio/ogg'
          WHEN 'mov,mp4,m4a,3gp,3g2,mj2' THEN document ->> 'content_type' = 'audio/mp4'
          WHEN 'matroska,webm' THEN document ->> 'content_type' = 'audio/webm'
          ELSE false END
        AND jsonb_typeof(document -> 'duration_ms') = 'number' AND document ->> 'duration_ms' ~ '^[0-9]{1,19}$'
        AND (document ->> 'duration_ms')::numeric BETWEEN 1 AND 9223372036854775807
        AND jsonb_typeof(document -> 'sample_rate') = 'number' AND document ->> 'sample_rate' ~ '^[0-9]{1,10}$'
        AND (document ->> 'sample_rate')::numeric BETWEEN 1 AND 2147483647
        AND jsonb_typeof(document -> 'channels') = 'number' AND document ->> 'channels' ~ '^[0-9]{1,10}$'
        AND (document ->> 'channels')::numeric BETWEEN 1 AND 2147483647) IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Institutional audio exact decoded metadata unavailable';
      END IF;
      RETURN NEW;
    END $guard$;
    CREATE TRIGGER cc_institutional_audio_inspection_guard BEFORE INSERT OR UPDATE OR DELETE ON jrc_contact_center_audio_inspections
      FOR EACH ROW EXECUTE FUNCTION cc_institutional_audio_inspection_guard();
  SQL

  def self.call
    SQL
  end
end
