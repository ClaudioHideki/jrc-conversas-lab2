CREATE FUNCTION jrc_bo_dossier_pin() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'Completion dossiers are immutable';
  END IF;
  IF NEW.number < 1 OR NOT EXISTS (
    SELECT 1 FROM jrc_crm_backoffice_requests r JOIN active_storage_blobs b ON b.id = NEW.archive_blob_id
    WHERE r.id = NEW.backoffice_request_id AND r.account_id = NEW.account_id
      AND b.content_type = 'application/gzip' AND b.metadata::jsonb ->> 'jrc_backoffice_dossier_archive' = 'true'
  ) THEN
    RAISE EXCEPTION 'Dossier must preserve its account, request and private archive';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER jrc_bo_dossier_pin BEFORE INSERT OR UPDATE OR DELETE ON jrc_backoffice_completion_dossiers
FOR EACH ROW EXECUTE FUNCTION jrc_bo_dossier_pin();

CREATE FUNCTION jrc_bo_dossier_blob_pin() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM jrc_backoffice_completion_dossiers WHERE archive_blob_id = OLD.id) THEN
    RAISE EXCEPTION 'Sealed archive blobs are immutable';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER jrc_bo_dossier_blob_pin BEFORE UPDATE OR DELETE ON active_storage_blobs
FOR EACH ROW EXECUTE FUNCTION jrc_bo_dossier_blob_pin();

CREATE FUNCTION jrc_bo_dossier_attachment_guard() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM jrc_backoffice_completion_dossiers WHERE archive_blob_id = NEW.blob_id)
    OR EXISTS (SELECT 1 FROM active_storage_blobs WHERE id = NEW.blob_id
      AND metadata::jsonb ->> 'jrc_backoffice_dossier_archive' = 'true') THEN
    RAISE EXCEPTION 'Sealed archives require the scoped dossier endpoint';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER jrc_bo_dossier_attachment_guard BEFORE INSERT OR UPDATE ON active_storage_attachments
FOR EACH ROW EXECUTE FUNCTION jrc_bo_dossier_attachment_guard();
