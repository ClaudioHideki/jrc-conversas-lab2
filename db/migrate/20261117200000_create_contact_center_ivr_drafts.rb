# frozen_string_literal: true

class CreateContactCenterIvrDrafts < ActiveRecord::Migration[7.1]
  DRAFTS = :jrc_contact_center_ivr_drafts
  VERSIONS = :jrc_contact_center_ivr_draft_versions

  def up
    return verify_existing! if table_exists?(DRAFTS) || table_exists?(VERSIONS)

    create_drafts
    create_versions
    install_guards
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Local IVR revision history requires a separately reviewed rollback'
  end

  private

  def create_drafts
    create_table DRAFTS do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :unit_id, null: false
      t.jsonb :scope_snapshot, null: false
      t.datetime :created_at, null: false
    end
    add_index DRAFTS, [:id, :account_id], unique: true, name: 'cc_ivr_draft_account_key'
    add_index DRAFTS, [:account_id, :unit_id, :id], name: 'cc_ivr_draft_unit_list'
    add_index :jrc_contact_center_units, [:id, :account_id], unique: true, name: 'cc_ivr_unit_account_key', if_not_exists: true
    add_foreign_key DRAFTS, :jrc_contact_center_units, column: [:unit_id, :account_id], primary_key: [:id, :account_id],
                                                   deferrable: :deferred, name: 'cc_ivr_draft_unit_account_fk'
    add_check_constraint DRAFTS, "jsonb_typeof(scope_snapshot) = 'object'", name: 'cc_ivr_draft_scope_object'
  end

  def create_versions
    create_table VERSIONS do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :ivr_draft_id, :actor_account_user_id, :actor_user_id, null: false
      t.integer :revision, null: false
      t.string :name, limit: 160, null: false
      t.string :status, limit: 16, null: false
      t.uuid :request_id, null: false
      t.jsonb :definition, null: false
      t.string :integrity_sha256, limit: 64, null: false
      t.datetime :created_at, null: false
    end
    constrain_versions
  end

  def constrain_versions
    add_index VERSIONS, [:account_id, :ivr_draft_id, :revision], unique: true, name: 'cc_ivr_revision_key'
    add_index VERSIONS, [:account_id, :request_id], unique: true, name: 'cc_ivr_request_key'
    add_foreign_key VERSIONS, DRAFTS, column: [:ivr_draft_id, :account_id], primary_key: [:id, :account_id],
                                    on_delete: :cascade, name: 'cc_ivr_version_account_fk'
    add_check_constraint VERSIONS, "revision > 0 AND btrim(name) <> '' AND status IN ('draft', 'archived')", name: 'cc_ivr_version_state'
    add_check_constraint VERSIONS, "jsonb_typeof(definition) = 'object' AND octet_length(definition::text) <= 1048576",
                         name: 'cc_ivr_definition_object'
    add_check_constraint VERSIONS, "integrity_sha256 ~ '^[0-9a-f]{64}$'", name: 'cc_ivr_version_digest'
  end

  def install_guards
    execute draft_guard_sql
    execute version_guard_sql
    execute first_version_sql
  end

  def draft_guard_sql
    <<~SQL
      CREATE FUNCTION cc_ivr_draft_guard() RETURNS trigger LANGUAGE plpgsql AS $guard$
      DECLARE source_unit record;
      BEGIN
        IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id) THEN RETURN OLD; END IF;
        IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'IVR draft identity is immutable'; END IF;
        SELECT * INTO STRICT source_unit FROM jrc_contact_center_units WHERE id = NEW.unit_id AND account_id = NEW.account_id;
        NEW.scope_snapshot = jsonb_build_object(
          'account_id', NEW.account_id::text, 'unit_id', NEW.unit_id::text, 'queue_id', NULL,
          'issuer_company_id', NULLIF(source_unit.settings ->> 'issuer_company_id', ''),
          'business_unit_id', NULLIF(source_unit.settings ->> 'business_unit_id', ''));
        RETURN NEW;
      END $guard$;
      CREATE TRIGGER cc_ivr_draft_guard BEFORE INSERT OR UPDATE OR DELETE ON jrc_contact_center_ivr_drafts
        FOR EACH ROW EXECUTE FUNCTION cc_ivr_draft_guard();
    SQL
  end

  def version_guard_sql
    <<~SQL
      CREATE FUNCTION cc_ivr_version_guard() RETURNS trigger LANGUAGE plpgsql AS $guard$
      DECLARE last_revision integer;
      BEGIN
        IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id) THEN RETURN OLD; END IF;
        IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'IVR revisions are immutable'; END IF;
        PERFORM 1 FROM jrc_contact_center_ivr_drafts WHERE id = NEW.ivr_draft_id AND account_id = NEW.account_id FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'IVR draft unavailable'; END IF;
        IF NOT EXISTS (SELECT 1 FROM account_users WHERE id = NEW.actor_account_user_id
            AND account_id = NEW.account_id AND user_id = NEW.actor_user_id) THEN
          RAISE EXCEPTION 'IVR revision actor unavailable';
        END IF;
        SELECT COALESCE(MAX(revision), 0) INTO last_revision FROM jrc_contact_center_ivr_draft_versions
          WHERE ivr_draft_id = NEW.ivr_draft_id AND account_id = NEW.account_id;
        IF NEW.revision <> last_revision + 1 THEN RAISE EXCEPTION 'IVR revision sequence conflict'; END IF;
        NEW.integrity_sha256 = encode(sha256(convert_to(jsonb_build_object(
          'name', NEW.name, 'status', NEW.status, 'definition', NEW.definition)::text, 'UTF8')), 'hex');
        RETURN NEW;
      END $guard$;
      CREATE TRIGGER cc_ivr_version_guard BEFORE INSERT OR UPDATE OR DELETE ON jrc_contact_center_ivr_draft_versions
        FOR EACH ROW EXECUTE FUNCTION cc_ivr_version_guard();
    SQL
  end

  def first_version_sql
    <<~SQL
      CREATE FUNCTION cc_ivr_first_version_guard() RETURNS trigger LANGUAGE plpgsql AS $guard$
      BEGIN
        IF EXISTS (SELECT 1 FROM jrc_contact_center_ivr_drafts WHERE id = NEW.id)
          AND NOT EXISTS (SELECT 1 FROM jrc_contact_center_ivr_draft_versions WHERE ivr_draft_id = NEW.id AND account_id = NEW.account_id) THEN
          RAISE EXCEPTION 'IVR draft requires its initial revision';
        END IF;
        RETURN NULL;
      END $guard$;
      CREATE CONSTRAINT TRIGGER cc_ivr_first_version_guard AFTER INSERT ON jrc_contact_center_ivr_drafts
        DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION cc_ivr_first_version_guard();
    SQL
  end

  def verify_existing!
    drafts = %w[id account_id unit_id scope_snapshot created_at]
    versions = %w[id account_id ivr_draft_id actor_account_user_id actor_user_id revision name status request_id
                  definition integrity_sha256 created_at]
    valid = schema_matches?(DRAFTS, drafts, %w[cc_ivr_draft_scope_object])
    valid &&= schema_matches?(VERSIONS, versions, %w[cc_ivr_definition_object cc_ivr_version_state cc_ivr_version_digest])
    guards = connection.select_values("SELECT tgname FROM pg_trigger WHERE NOT tgisinternal AND tgname LIKE 'cc_ivr_%'").sort
    valid &&= guards == %w[cc_ivr_draft_guard cc_ivr_first_version_guard cc_ivr_version_guard]
    raise ActiveRecord::MigrationError, 'Unexpected IVR ledger schema; review before reexecution' unless valid
  end

  def schema_matches?(table, columns, checks)
    return false unless table_exists?(table)

    connection.columns(table).map(&:name).sort == columns.sort && connection.foreign_keys(table).length == 2 &&
      connection.check_constraints(table).map(&:name).sort == checks.sort
  end
end
