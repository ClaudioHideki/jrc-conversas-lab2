# frozen_string_literal: true

class CreateContactCenterAcwForms < ActiveRecord::Migration[7.1]
  TEMPLATES = :jrc_contact_center_acw_form_templates
  VERSIONS = :jrc_contact_center_acw_form_versions
  # Compact JSON remains limited to262144bytes in the native validator.
  # JSONB text needs up to5450extra separator spaces for50fields/100options.
  DEFINITION_BYTES = 270_336

  def up
    return verify_existing! if table_exists?(TEMPLATES) || table_exists?(VERSIONS)

    create_templates
    create_versions
    execute template_guard_sql
    execute version_guard_sql
    execute first_version_sql
    change_table_comment TEMPLATES, schema_receipt
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'ACW form revision history requires a separately reviewed rollback'
  end

  private

  def create_templates
    create_table TEMPLATES do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.jsonb :scope_snapshot, null: false
      t.datetime :created_at, null: false
    end
    add_index TEMPLATES, [:id, :account_id], unique: true, name: 'cc_acw_form_account_key'
    add_check_constraint TEMPLATES, "jsonb_typeof(scope_snapshot) = 'object'", name: 'cc_acw_form_scope_object'
  end

  def create_versions
    create_table VERSIONS do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :acw_form_template_id, :actor_account_user_id, :actor_user_id, null: false
      t.integer :revision, null: false
      t.string :name, limit: 160, null: false
      t.string :description, limit: 1000, null: false, default: ''
      t.string :status, limit: 16, null: false
      t.uuid :request_id, null: false
      t.jsonb :definition, null: false
      t.string :integrity_sha256, limit: 64, null: false
      t.datetime :created_at, null: false
    end
    constrain_versions
  end

  def constrain_versions
    add_index VERSIONS, [:account_id, :acw_form_template_id, :revision], unique: true, name: 'cc_acw_form_revision_key'
    add_index VERSIONS, [:account_id, :request_id], unique: true, name: 'cc_acw_form_request_key'
    add_foreign_key VERSIONS, TEMPLATES, column: [:acw_form_template_id, :account_id], primary_key: [:id, :account_id],
                                         on_delete: :cascade, name: 'cc_acw_form_version_account_fk'
    add_check_constraint VERSIONS, "revision > 0 AND btrim(name) <> '' AND " \
                                  "status::text IN ('active'::text, 'archived'::text)", name: 'cc_acw_form_version_state'
    add_check_constraint VERSIONS, "jsonb_typeof(definition) = 'object' AND octet_length(definition::text) <= #{DEFINITION_BYTES} " \
                                   "AND definition ? 'fields' " \
                                   "AND jsonb_typeof(definition -> 'fields') = 'array' " \
                                   "AND jsonb_array_length(definition -> 'fields') BETWEEN 1 AND 50 " \
                                   "AND definition - 'fields' = '{}'::jsonb", name: 'cc_acw_form_definition_object'
    add_check_constraint VERSIONS, "integrity_sha256 ~ '^[0-9a-f]{64}$'", name: 'cc_acw_form_version_digest'
  end

  def template_guard_sql
    <<~SQL.squish
      CREATE FUNCTION cc_acw_form_template_guard() RETURNS trigger LANGUAGE plpgsql AS $guard$
      BEGIN
        IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id) THEN RETURN OLD; END IF;
        IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'ACW form identity is immutable'; END IF;
        NEW.scope_snapshot = jsonb_build_object('account_id', NEW.account_id::text);
        RETURN NEW;
      END $guard$;
      CREATE TRIGGER cc_acw_form_template_guard BEFORE INSERT OR UPDATE OR DELETE ON jrc_contact_center_acw_form_templates
        FOR EACH ROW EXECUTE FUNCTION cc_acw_form_template_guard();
    SQL
  end

  def version_guard_sql
    <<~SQL.squish
      CREATE FUNCTION cc_acw_form_version_guard() RETURNS trigger LANGUAGE plpgsql AS $guard$
      DECLARE last_revision integer;
      BEGIN
        IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id) THEN RETURN OLD; END IF;
        IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'ACW form revisions are immutable'; END IF;
        PERFORM 1 FROM jrc_contact_center_acw_form_templates
          WHERE id = NEW.acw_form_template_id AND account_id = NEW.account_id FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'ACW form unavailable'; END IF;
        #{version_actor_sql}
        SELECT COALESCE(MAX(revision), 0) INTO last_revision FROM jrc_contact_center_acw_form_versions
          WHERE acw_form_template_id = NEW.acw_form_template_id AND account_id = NEW.account_id;
        IF NEW.revision <> last_revision + 1 THEN RAISE EXCEPTION 'ACW form revision sequence conflict'; END IF;
        #{version_digest_sql}
        RETURN NEW;
      END $guard$;
      CREATE TRIGGER cc_acw_form_version_guard BEFORE INSERT OR UPDATE OR DELETE ON jrc_contact_center_acw_form_versions
        FOR EACH ROW EXECUTE FUNCTION cc_acw_form_version_guard();
    SQL
  end

  def version_digest_sql
    <<~SQL.squish
      NEW.integrity_sha256 = encode(sha256(convert_to(jsonb_build_object(
        'name', NEW.name, 'description', NEW.description, 'status', NEW.status,
        'definition', NEW.definition)::text, 'UTF8')), 'hex');
    SQL
  end

  def version_actor_sql
    <<~SQL.squish
      IF NOT EXISTS (SELECT 1 FROM account_users WHERE id = NEW.actor_account_user_id
          AND account_id = NEW.account_id AND user_id = NEW.actor_user_id) THEN
        RAISE EXCEPTION 'ACW form revision actor unavailable';
      END IF;
    SQL
  end

  def first_version_sql
    <<~SQL.squish
      CREATE FUNCTION cc_acw_form_first_version_guard() RETURNS trigger LANGUAGE plpgsql AS $guard$
      BEGIN
        IF EXISTS (SELECT 1 FROM jrc_contact_center_acw_form_templates WHERE id = NEW.id)
          AND NOT EXISTS (SELECT 1 FROM jrc_contact_center_acw_form_versions
            WHERE acw_form_template_id = NEW.id AND account_id = NEW.account_id) THEN
          RAISE EXCEPTION 'ACW form requires its initial revision';
        END IF;
        RETURN NULL;
      END $guard$;
      CREATE CONSTRAINT TRIGGER cc_acw_form_first_version_guard AFTER INSERT ON jrc_contact_center_acw_form_templates
        DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION cc_acw_form_first_version_guard();
    SQL
  end

  def verify_existing!
    templates = %w[id account_id scope_snapshot created_at]
    versions = %w[id account_id acw_form_template_id actor_account_user_id actor_user_id revision name description status request_id
                  definition integrity_sha256 created_at]
    valid = schema_matches?(TEMPLATES, templates, %w[cc_acw_form_scope_object], 1)
    valid &&= schema_matches?(VERSIONS, versions,
                              %w[cc_acw_form_definition_object cc_acw_form_version_state cc_acw_form_version_digest], 2)
    guards = connection.select_values("SELECT tgname FROM pg_trigger WHERE NOT tgisinternal AND tgname LIKE 'cc_acw_form_%'").sort
    valid &&= guards == %w[cc_acw_form_first_version_guard cc_acw_form_template_guard cc_acw_form_version_guard]
    valid &&= connection.table_comment(TEMPLATES) == schema_receipt
    raise ActiveRecord::MigrationError, 'Unexpected ACW form ledger schema; review before reexecution' unless valid
  end

  def schema_receipt
    SchemaReceipt.new(connection).call
  end

  def schema_matches?(table, columns, checks, foreign_keys)
    return false unless table_exists?(table)

    connection.columns(table).map(&:name).sort == columns.sort && connection.foreign_keys(table).length == foreign_keys &&
      connection.check_constraints(table).map(&:name).sort == checks.sort
  end

  # Structure only: no OIDs, database names, rows or actors enter the receipt.
  class SchemaReceipt
    TABLES = [CreateContactCenterAcwForms::TEMPLATES, CreateContactCenterAcwForms::VERSIONS].freeze

    def initialize(connection)
      @connection = connection
      @tables = TABLES.map { |name| "#{@connection.quote(name.to_s)}::regclass" }.join(',')
    end

    def call
      "jrc_cc_acw_forms_v1:#{Digest::SHA256.hexdigest(components.values.to_json)}"
    end

    def components
      { columns: columns, constraints: constraints, triggers: triggers, functions: functions, indexes: indexes }
    end

    private

    def columns
      TABLES.map do |table|
        [table, @connection.columns(table).map { |column| [column.name, column.sql_type, column.null, column.default] }]
      end
    end

    def constraints
      @connection.select_rows('SELECT c.relname, x.conname, pg_get_constraintdef(x.oid, true) FROM pg_constraint x ' \
                              "JOIN pg_class c ON c.oid = x.conrelid WHERE c.oid IN (#{@tables}) ORDER BY c.relname, x.conname")
    end

    def triggers
      @connection.select_rows('SELECT tgname, pg_get_triggerdef(oid, true) FROM pg_trigger ' \
                              "WHERE NOT tgisinternal AND tgrelid IN (#{@tables}) ORDER BY tgname")
    end

    def functions
      @connection.select_rows('SELECT proname, pg_get_functiondef(oid) FROM pg_proc ' \
                              "WHERE oid IN (SELECT tgfoid FROM pg_trigger WHERE NOT tgisinternal AND tgrelid IN (#{@tables})) " \
                              'ORDER BY proname')
    end

    def indexes
      TABLES.map do |table|
        [table, @connection.indexes(table).map { |index| [index.name, index.columns, index.unique] }.sort]
      end
    end
  end
end
