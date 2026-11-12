class AddBackofficeDocumentValidity < ActiveRecord::Migration[7.1]
  def up
    # Old files/decisions retain null validity. No expiry is inferred from OCR.
    add_column :jrc_backoffice_document_decisions, :expires_on, :date
    add_column :jrc_backoffice_document_decisions, :validity_timezone, :string
    add_check_constraint :jrc_backoffice_document_decisions,
      "(expires_on IS NULL AND validity_timezone IS NULL) OR " \
      "(expires_on IS NOT NULL AND expires_on BETWEEN DATE '0001-01-01' AND DATE '9999-12-31' AND " \
      "validity_timezone IS NOT NULL AND char_length(validity_timezone) BETWEEN 1 AND 100)",
      name: 'bo_document_validity_pair'
    execute <<~SQL
      CREATE FUNCTION jrc_bo_document_validity_guard() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF TG_OP = 'UPDATE' AND (
          NEW.expires_on IS DISTINCT FROM OLD.expires_on OR
          NEW.validity_timezone IS DISTINCT FROM OLD.validity_timezone
        ) THEN
          RAISE EXCEPTION 'Document validity is immutable; append a new decision' USING ERRCODE = '23514';
        END IF;
        IF NEW.expires_on IS NOT NULL AND NOT EXISTS (
          SELECT 1 FROM pg_timezone_names WHERE name = NEW.validity_timezone
        ) THEN
          RAISE EXCEPTION 'Unknown document validity time zone' USING ERRCODE = '23514';
        END IF;
        RETURN NEW;
      END;
      $$;
      CREATE TRIGGER jrc_bo_document_validity_guard
        BEFORE INSERT OR UPDATE OF expires_on, validity_timezone
        ON jrc_backoffice_document_decisions
        FOR EACH ROW EXECUTE FUNCTION jrc_bo_document_validity_guard();
    SQL
  end

  def down
    execute 'DROP TRIGGER jrc_bo_document_validity_guard ON jrc_backoffice_document_decisions'
    execute 'DROP FUNCTION jrc_bo_document_validity_guard()'
    remove_check_constraint :jrc_backoffice_document_decisions, name: 'bo_document_validity_pair'
    remove_column :jrc_backoffice_document_decisions, :validity_timezone
    remove_column :jrc_backoffice_document_decisions, :expires_on
  end
end
