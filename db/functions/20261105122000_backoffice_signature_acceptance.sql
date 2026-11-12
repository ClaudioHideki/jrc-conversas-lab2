CREATE FUNCTION jrc_bo_signature_acceptance_pin() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'Signature acceptances are immutable';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM jrc_backoffice_signature_artifact_bundles b
    JOIN jrc_backoffice_signature_deliveries d ON d.id = b.delivery_id
    JOIN jrc_crm_contracts c ON c.id = NEW.contract_id AND c.account_id = NEW.account_id
    JOIN jrc_backoffice_document_versions v ON v.id = b.signed_document_id AND v.account_id = NEW.account_id
    JOIN active_storage_attachments a ON a.record_type = 'JrcBackoffice::DocumentVersion'
      AND a.record_id = v.id AND a.name = 'file' AND a.blob_id = NEW.signed_blob_id
    WHERE b.id = NEW.bundle_id AND b.account_id = NEW.account_id
      AND d.contract_id = c.id AND d.account_id = NEW.account_id
  ) THEN
    RAISE EXCEPTION 'Signature acceptance must preserve the exact account, contract and signed file';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER jrc_bo_signature_acceptance_pin BEFORE INSERT OR UPDATE OR DELETE ON jrc_backoffice_signature_acceptances
FOR EACH ROW EXECUTE FUNCTION jrc_bo_signature_acceptance_pin();

CREATE OR REPLACE FUNCTION jrc_bo_private_attachment() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP <> 'INSERT' AND OLD.record_type = 'JrcBackoffice::DocumentVersion' THEN
    RAISE EXCEPTION 'Document version files are immutable';
  END IF;
  IF TG_OP <> 'INSERT' AND OLD.record_type = 'JrcCrm::Contract' AND OLD.name = 'signed_document'
    AND EXISTS (SELECT 1 FROM jrc_backoffice_signature_acceptances WHERE contract_id = OLD.record_id) THEN
    RAISE EXCEPTION 'Accepted signed contract files are immutable';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  IF (EXISTS (SELECT 1 FROM jrc_backoffice_contract_versions WHERE pdf_blob_id = NEW.blob_id)
    OR EXISTS (SELECT 1 FROM jrc_backoffice_document_scans WHERE source_blob_id = NEW.blob_id)
    OR EXISTS (SELECT 1 FROM active_storage_attachments
      WHERE blob_id = NEW.blob_id AND record_type = 'JrcBackoffice::DocumentVersion'))
    AND NOT (NEW.record_type = 'JrcCrm::Contract' AND NEW.name = 'signed_document'
      AND EXISTS (SELECT 1 FROM jrc_backoffice_signature_acceptances
        WHERE contract_id = NEW.record_id AND signed_blob_id = NEW.blob_id)) THEN
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
