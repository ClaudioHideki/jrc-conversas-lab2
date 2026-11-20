# frozen_string_literal: true

class JrcContactCenter::AudioFileOriginSql
  SQL = <<~SQL.squish.freeze
    CREATE FUNCTION cc_institutional_audio_asset_guard() RETURNS trigger LANGUAGE plpgsql AS $guard$
    BEGIN
      IF (NEW.id, NEW.account_id, NEW.unit_id) IS DISTINCT FROM (OLD.id, OLD.account_id, OLD.unit_id) THEN
        RAISE EXCEPTION 'Institutional audio origin is immutable';
      END IF;
      RETURN NEW;
    END $guard$;
    CREATE TRIGGER cc_institutional_audio_asset_guard BEFORE UPDATE ON jrc_contact_center_audio_assets
      FOR EACH ROW EXECUTE FUNCTION cc_institutional_audio_asset_guard();

    CREATE FUNCTION cc_institutional_audio_version_guard() RETURNS trigger LANGUAGE plpgsql AS $guard$
    DECLARE stored active_storage_blobs%ROWTYPE; previous_number integer;
    BEGIN
      IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'Institutional audio versions are immutable'; END IF;
      PERFORM 1 FROM accounts WHERE id = NEW.account_id FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'Institutional audio account unavailable'; END IF;
      PERFORM 1 FROM jrc_contact_center_audio_assets
        WHERE id = NEW.audio_asset_id AND account_id = NEW.account_id AND unit_id = NEW.unit_id FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'Institutional audio asset origin unavailable'; END IF;
      IF NOT EXISTS (SELECT 1 FROM account_users WHERE account_id = NEW.account_id AND user_id = NEW.created_by_id) THEN
        RAISE EXCEPTION 'Institutional audio uploader account unavailable';
      END IF;
      SELECT * INTO stored FROM active_storage_blobs WHERE id = NEW.blob_id FOR KEY SHARE;
      IF NOT FOUND OR stored.byte_size IS DISTINCT FROM NEW.byte_size OR stored.content_type IS DISTINCT FROM NEW.content_type
        OR stored.filename IS DISTINCT FROM NEW.file_name
        OR NOT cc_institutional_audio_owned(stored.metadata::text) THEN
        RAISE EXCEPTION 'Institutional audio owned bytes unavailable';
      END IF;
      IF EXISTS (SELECT 1 FROM active_storage_attachments WHERE blob_id = NEW.blob_id) THEN
        RAISE EXCEPTION 'Institutional audio cannot reuse an attached file';
      END IF;
      IF EXISTS (SELECT 1 FROM jrc_contact_center_audio_versions WHERE blob_id = NEW.blob_id
        AND (account_id IS DISTINCT FROM NEW.account_id OR unit_id IS DISTINCT FROM NEW.unit_id)) THEN
        RAISE EXCEPTION 'Institutional audio bytes cannot cross a unit';
      END IF;
      SELECT MAX(number) INTO previous_number FROM jrc_contact_center_audio_versions
        WHERE account_id = NEW.account_id AND unit_id = NEW.unit_id AND audio_asset_id = NEW.audio_asset_id;
      IF NEW.number <> COALESCE(previous_number, 0) + 1 THEN RAISE EXCEPTION 'Institutional audio sequence conflict'; END IF;
      RETURN NEW;
    END $guard$;
    CREATE TRIGGER cc_institutional_audio_version_guard BEFORE INSERT OR UPDATE OR DELETE ON jrc_contact_center_audio_versions
      FOR EACH ROW EXECUTE FUNCTION cc_institutional_audio_version_guard();
  SQL

  def self.call
    SQL
  end
end
