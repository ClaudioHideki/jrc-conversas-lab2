# frozen_string_literal: true

# New private child state only; no historical attendance or rule snapshot is rewritten.
class CreateContactCenterQualificationForms < ActiveRecord::Migration[7.1]
  TABLE = :jrc_contact_center_qualification_forms

  def up
    return verify_existing! if table_exists?(TABLE)

    create_response_table
    constrain_responses
    execute response_guard
    execute qualification_guard
    execute <<~SQL.squish
      CREATE TRIGGER jrc_cc_qualification_forms_immutable
      BEFORE INSERT OR UPDATE OR DELETE ON jrc_contact_center_qualification_forms
      FOR EACH ROW EXECUTE FUNCTION jrc_cc_qualification_form_guard_v1();
      CREATE TRIGGER jrc_cc_qualification_forms_source
      BEFORE UPDATE ON jrc_contact_center_qualifications
      FOR EACH ROW EXECUTE FUNCTION jrc_cc_qualification_form_source_guard_v1();
    SQL
    change_table_comment TABLE, schema_receipt
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Private qualification evidence must not be discarded automatically'
  end

  private

  def create_response_table
    create_table :jrc_contact_center_qualification_forms do |t|
      t.bigint :account_id, null: false
      t.bigint :qualification_id, null: false
      t.bigint :unit_id, :queue_id
      t.jsonb :snapshot, null: false
      t.jsonb :answers, null: false, default: {}
      t.timestamps null: false
    end
  end

  def constrain_responses
    add_index :jrc_contact_center_qualification_forms, :qualification_id, unique: true, name: 'jrc_cc_qualification_forms_identity'
    add_index :jrc_contact_center_qualification_forms, :account_id
    add_foreign_key :jrc_contact_center_qualification_forms, :accounts, on_delete: :cascade
    add_foreign_key :jrc_contact_center_qualification_forms, :jrc_contact_center_qualifications,
                    column: :qualification_id, on_delete: :cascade
    add_check_constraint :jrc_contact_center_qualification_forms,
                         "COALESCE(jsonb_typeof(snapshot) = 'object' AND jsonb_typeof(answers) = 'object', false)",
                         name: 'jrc_cc_qualification_forms_objects'
    add_check_constraint :jrc_contact_center_qualification_forms,
                         'octet_length(snapshot::text) <= 262144 AND octet_length(answers::text) <= 262144',
                         name: 'jrc_cc_qualification_forms_bounds'
  end

  def schema_receipt
    SchemaReceiptQuery.new(connection).call
  end

  def verify_existing!
    SchemaReceiptQuery.new(connection).verify!
  end

  def response_guard
    <<~SQL.squish
      CREATE FUNCTION jrc_cc_qualification_form_guard_v1() RETURNS trigger LANGUAGE plpgsql AS $guard$
      DECLARE parent_account bigint; parent_member bigint; parent_completed timestamp;
      BEGIN
        #{response_delete_sql}
        #{response_identity_sql}
        #{response_scope_sql}
        #{response_origin_sql}
        #{response_origin_scope_sql}
        #{response_versions_sql}
        #{response_update_sql}
        RETURN NEW;
      END;
      $guard$;
    SQL
  end

  def response_delete_sql
    <<~SQL.squish
      IF TG_OP = 'DELETE' THEN
        IF EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id)
           AND EXISTS (SELECT 1 FROM jrc_contact_center_qualifications WHERE id = OLD.qualification_id) THEN
          RAISE EXCEPTION 'jrc_cc_qualification_form_history_immutable';
        END IF;
        RETURN OLD;
      END IF;
    SQL
  end

  def response_identity_sql
    <<~SQL.squish
      SELECT account_id, account_user_id, completed_at INTO parent_account, parent_member, parent_completed
        FROM jrc_contact_center_qualifications WHERE id = NEW.qualification_id;
      IF NOT FOUND OR parent_account IS DISTINCT FROM NEW.account_id
         OR NOT COALESCE(NEW.snapshot ->> 'version' = '1'
           AND jsonb_typeof(NEW.snapshot -> 'bindings') = 'array'
           AND jsonb_array_length(NEW.snapshot -> 'bindings') BETWEEN 1 AND 100
           AND jsonb_typeof(NEW.snapshot -> 'reason_codes') = 'array'
           AND jsonb_typeof(NEW.snapshot -> 'origin') = 'object'
           AND NEW.snapshot #>> '{origin,qualification_id}' = NEW.qualification_id::text
           AND NEW.snapshot #>> '{origin,account_id}' = NEW.account_id::text
           AND NEW.snapshot #>> '{origin,account_user_id}' = parent_member::text, false) THEN
        RAISE EXCEPTION 'jrc_cc_qualification_form_identity';
      END IF;
    SQL
  end

  def response_scope_sql
    <<~SQL.squish
      IF NEW.unit_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM jrc_contact_center_units
          WHERE id = NEW.unit_id AND account_id = NEW.account_id) THEN
        RAISE EXCEPTION 'jrc_cc_qualification_form_unit';
      END IF;
      IF NEW.queue_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM jrc_contact_center_queues
          WHERE id = NEW.queue_id AND account_id = NEW.account_id
            AND (NEW.unit_id IS NULL OR unit_id = NEW.unit_id)) THEN
        RAISE EXCEPTION 'jrc_cc_qualification_form_queue';
      END IF;
      IF TG_OP = 'INSERT' AND parent_completed IS NOT NULL THEN
        RAISE EXCEPTION 'jrc_cc_qualification_form_already_completed';
      END IF;
    SQL
  end

  def response_origin_sql
    <<~SQL.squish
      IF TG_OP = 'INSERT' AND NOT EXISTS (
        SELECT 1 FROM jrc_contact_center_agent_state_events
        WHERE account_id = NEW.account_id
          AND account_user_id = parent_member
          AND external_event_id = 'qualification:' || NEW.qualification_id::text || ':pending'
          AND source = 'jrc_conversas' AND state = 'acw'
          AND metadata -> 'acw_rule_snapshot_v1' = NEW.snapshot -> 'origin'
      ) THEN
        RAISE EXCEPTION 'jrc_cc_qualification_form_origin';
      END IF;
    SQL
  end

  def response_origin_scope_sql
    <<~SQL.squish
      IF TG_OP = 'INSERT' AND NEW.snapshot #>> '{origin,queue_id}' IS NOT NULL
         AND NEW.queue_id::text IS DISTINCT FROM NEW.snapshot #>> '{origin,queue_id}' THEN
        RAISE EXCEPTION 'jrc_cc_qualification_form_original_queue';
      END IF;
    SQL
  end

  def response_versions_sql
    <<~SQL.squish
      IF TG_OP = 'INSERT' AND EXISTS (
        SELECT 1 FROM jsonb_array_elements(NEW.snapshot -> 'bindings') AS pin
        LEFT JOIN jrc_contact_center_acw_form_versions AS v
          ON v.account_id = NEW.account_id
          AND v.acw_form_template_id = (pin ->> 'form_id')::bigint
          AND v.revision = (pin ->> 'revision')::integer
          AND v.status = 'active' AND v.integrity_sha256 = pin ->> 'integrity_sha256'
        WHERE v.id IS NULL
      ) THEN
        RAISE EXCEPTION 'jrc_cc_qualification_form_version';
      END IF;
    SQL
  end

  def response_update_sql
    <<~SQL.squish
      IF TG_OP = 'UPDATE' THEN
        IF ROW(NEW.account_id, NEW.qualification_id, NEW.unit_id, NEW.queue_id, NEW.snapshot)
           IS DISTINCT FROM ROW(OLD.account_id, OLD.qualification_id, OLD.unit_id, OLD.queue_id, OLD.snapshot) THEN
          RAISE EXCEPTION 'jrc_cc_qualification_form_snapshot_immutable';
        END IF;
        IF parent_completed IS NOT NULL AND NEW.answers IS DISTINCT FROM OLD.answers THEN
          RAISE EXCEPTION 'jrc_cc_qualification_form_answers_sealed';
        END IF;
      END IF;
    SQL
  end

  def qualification_guard
    <<~SQL.squish
      CREATE FUNCTION jrc_cc_qualification_form_source_guard_v1() RETURNS trigger LANGUAGE plpgsql AS $guard$
      BEGIN
        IF EXISTS (SELECT 1 FROM jrc_contact_center_qualification_forms WHERE qualification_id = OLD.id) THEN
          IF ROW(NEW.account_id, NEW.account_user_id, NEW.channel, NEW.call_session_id, NEW.conversation_id, NEW.conversation_cycle)
             IS DISTINCT FROM ROW(OLD.account_id, OLD.account_user_id, OLD.channel, OLD.call_session_id, OLD.conversation_id, OLD.conversation_cycle) THEN
            RAISE EXCEPTION 'jrc_cc_qualification_form_source_immutable';
          END IF;
          IF OLD.completed_at IS NOT NULL AND
             ROW(NEW.completed_at, NEW.reason_code, NEW.outcome_code, NEW.notes, NEW.started_at, NEW.acw_limit_seconds, NEW.duration_seconds)
             IS DISTINCT FROM
             ROW(OLD.completed_at, OLD.reason_code, OLD.outcome_code, OLD.notes, OLD.started_at, OLD.acw_limit_seconds, OLD.duration_seconds) THEN
            RAISE EXCEPTION 'jrc_cc_qualification_form_completion_sealed';
          END IF;
        END IF;
        RETURN NEW;
      END;
      $guard$;
    SQL
  end
end

# Self-contained read-only structural receipt, including the owned trigger on the native parent table.
class CreateContactCenterQualificationForms::SchemaReceiptQuery
  def initialize(connection)
    @connection = connection
    @table = "#{connection.quote(CreateContactCenterQualificationForms::TABLE.to_s)}::regclass"
  end

  def call
    "jrc_cc_qualification_forms_v1:#{Digest::SHA256.hexdigest(JSON.generate(components))}"
  end

  def verify!
    table = CreateContactCenterQualificationForms::TABLE
    columns = %w[id account_id qualification_id unit_id queue_id snapshot answers created_at updated_at]
    checks = %w[jrc_cc_qualification_forms_bounds jrc_cc_qualification_forms_objects]
    valid = @connection.columns(table).map(&:name).sort == columns.sort && @connection.foreign_keys(table).length == 2 &&
            @connection.check_constraints(table).map(&:name).sort == checks && @connection.table_comment(table) == call
    raise ActiveRecord::MigrationError, 'Unexpected private qualification form schema; review before reexecution' unless valid
  end

  private

  def components
    table = CreateContactCenterQualificationForms::TABLE
    columns = @connection.columns(table).map { |column| [column.name, column.sql_type, column.null, column.default] }
    indexes = @connection.indexes(table).map { |index| [index.name, index.columns, index.unique, index.where] }.sort
    [columns, constraints, triggers, functions, indexes]
  end

  def constraints
    @connection.select_rows('SELECT conname, pg_get_constraintdef(oid, true) FROM pg_constraint ' \
                            "WHERE conrelid = #{@table} ORDER BY conname")
  end

  def trigger_scope
    "(tgrelid = #{@table} OR (tgrelid = 'jrc_contact_center_qualifications'::regclass " \
      "AND tgname = 'jrc_cc_qualification_forms_source'))"
  end

  def triggers
    @connection.select_rows('SELECT tgname, pg_get_triggerdef(oid, true) FROM pg_trigger ' \
                            "WHERE NOT tgisinternal AND #{trigger_scope} ORDER BY tgname")
  end

  def functions
    @connection.select_rows('SELECT proname, pg_get_functiondef(oid) FROM pg_proc WHERE oid IN ' \
                            "(SELECT tgfoid FROM pg_trigger WHERE NOT tgisinternal AND #{trigger_scope}) ORDER BY proname")
  end
end
