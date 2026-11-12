CREATE OR REPLACE FUNCTION jrc_bo_document_scan_pin() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  -- ActiveStorage touches its owner after the initial file link. It may
  -- update only this technical timestamp, never the version's evidence.
  IF TG_TABLE_NAME = 'jrc_backoffice_document_versions' AND TG_OP = 'UPDATE'
    AND (to_jsonb(NEW) - 'updated_at') = (to_jsonb(OLD) - 'updated_at') THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'Document security observations are immutable';
END;
$$;

CREATE TRIGGER jrc_bo_document_scan_pin BEFORE UPDATE OR DELETE ON jrc_backoffice_document_scans
FOR EACH ROW EXECUTE FUNCTION jrc_bo_document_scan_pin();
CREATE TRIGGER jrc_bo_document_version_pin BEFORE UPDATE OR DELETE ON jrc_backoffice_document_versions
FOR EACH ROW EXECUTE FUNCTION jrc_bo_document_scan_pin();

CREATE FUNCTION jrc_bo_private_attachment() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP <> 'INSERT' AND OLD.record_type = 'JrcBackoffice::DocumentVersion' THEN
    RAISE EXCEPTION 'Document version files are immutable';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  IF EXISTS (SELECT 1 FROM jrc_backoffice_contract_versions WHERE pdf_blob_id = NEW.blob_id)
    OR EXISTS (SELECT 1 FROM jrc_backoffice_document_scans WHERE source_blob_id = NEW.blob_id)
    OR EXISTS (SELECT 1 FROM active_storage_attachments
      WHERE blob_id = NEW.blob_id AND record_type = 'JrcBackoffice::DocumentVersion') THEN
    RAISE EXCEPTION 'Private Backoffice files cannot be relinked';
  END IF;
  IF NEW.record_type = 'JrcBackoffice::DocumentVersion' THEN
    PERFORM 1 FROM jrc_backoffice_document_versions WHERE id = NEW.record_id FOR NO KEY UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Document version required';
    END IF;
    IF NEW.name <> 'file' OR EXISTS (SELECT 1 FROM active_storage_attachments
      WHERE record_type = NEW.record_type AND record_id = NEW.record_id) THEN
      RAISE EXCEPTION 'Document versions have one immutable file';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER jrc_bo_private_attachment BEFORE INSERT OR UPDATE OR DELETE ON active_storage_attachments
FOR EACH ROW EXECUTE FUNCTION jrc_bo_private_attachment();
