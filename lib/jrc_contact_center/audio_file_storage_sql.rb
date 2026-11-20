# frozen_string_literal: true

class JrcContactCenter::AudioFileStorageSql
  SQL = <<~SQL.squish.freeze
    CREATE FUNCTION cc_institutional_audio_owned(metadata text) RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $owned$
    DECLARE document jsonb;
    BEGIN
      IF metadata IS NULL OR position('"jrc_contact_center_institutional_audio"' in metadata) = 0 THEN RETURN false; END IF;
      document := metadata::jsonb;
      RETURN jsonb_typeof(document) = 'object'
        AND COALESCE(document -> 'jrc_contact_center_institutional_audio', 'false'::jsonb) = 'true'::jsonb;
    EXCEPTION WHEN data_exception THEN
      RETURN false;
    END $owned$;

    CREATE FUNCTION cc_institutional_audio_blob_guard() RETURNS trigger LANGUAGE plpgsql AS $guard$
    DECLARE linked boolean; owned boolean;
    BEGIN
      SELECT EXISTS (SELECT 1 FROM jrc_contact_center_audio_versions WHERE blob_id = OLD.id) INTO linked;
      IF TG_OP = 'DELETE' THEN
        IF linked THEN RAISE foreign_key_violation USING MESSAGE = 'Institutional audio historical bytes are protected'; END IF;
        RETURN OLD;
      END IF;
      owned := cc_institutional_audio_owned(OLD.metadata::text);
      IF linked OR owned THEN
        IF (NEW.id, NEW.key, NEW.service_name, NEW.checksum, NEW.byte_size, NEW.content_type, NEW.filename)
          IS DISTINCT FROM (OLD.id, OLD.key, OLD.service_name, OLD.checksum, OLD.byte_size, OLD.content_type, OLD.filename)
          OR NOT cc_institutional_audio_owned(NEW.metadata::text) THEN
          RAISE EXCEPTION 'Institutional audio storage identity is immutable';
        END IF;
      END IF;
      RETURN NEW;
    END $guard$;
    CREATE TRIGGER cc_institutional_audio_blob_guard BEFORE UPDATE OR DELETE ON active_storage_blobs
      FOR EACH ROW EXECUTE FUNCTION cc_institutional_audio_blob_guard();

    CREATE FUNCTION cc_institutional_audio_attachment_guard() RETURNS trigger LANGUAGE plpgsql AS $guard$
    BEGIN
      IF EXISTS (SELECT 1 FROM jrc_contact_center_audio_versions WHERE blob_id = NEW.blob_id)
        OR EXISTS (SELECT 1 FROM active_storage_blobs WHERE id = NEW.blob_id
          AND cc_institutional_audio_owned(metadata::text)) THEN
        RAISE EXCEPTION 'Institutional audio bytes cannot use a generic attachment owner';
      END IF;
      RETURN NEW;
    END $guard$;
    CREATE TRIGGER cc_institutional_audio_attachment_guard BEFORE INSERT OR UPDATE ON active_storage_attachments
      FOR EACH ROW EXECUTE FUNCTION cc_institutional_audio_attachment_guard();
  SQL

  def self.call
    SQL
  end
end
