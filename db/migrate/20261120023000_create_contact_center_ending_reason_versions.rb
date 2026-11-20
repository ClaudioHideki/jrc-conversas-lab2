# frozen_string_literal: true

# New calls pin the existing account catalogue; old calls deliberately remain unpinned.
class CreateContactCenterEndingReasonVersions < ActiveRecord::Migration[7.1]
  TABLE = :jrc_contact_center_ending_reason_versions
  CALLS = :jrc_contact_center_call_sessions
  ORIGIN_SQL_SHA256 = '109e09f227ab4e04d33fdf61d609e21020fbd4d22b2982407adc1da6e85f0cbb'

  def up
    source = Rails.root.join('lib/jrc_contact_center/ending_reason_origin_sql.rb')
    matches = Digest::SHA256.file(source).hexdigest == ORIGIN_SQL_SHA256
    raise ActiveRecord::MigrationError, 'Ending reason SQL source changed; review before migration' unless matches

    return verify_existing! if table_exists?(TABLE)

    create_versions
    execute version_guard_sql
    backfill_proven_history!
    add_column CALLS, :ending_reason_version_id, :bigint
    add_foreign_key CALLS, TABLE, column: [:ending_reason_version_id, :account_id], primary_key: [:id, :account_id],
                                 deferrable: :deferred, name: 'cc_ending_reason_call_account_fk'
    add_index CALLS, :ending_reason_version_id, name: 'cc_ending_reason_call_version'
    execute call_guard_sql
    execute JrcContactCenter::EndingReasonOriginSql.new.call
    change_table_comment TABLE, schema_receipt
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Ending reason call history requires a separately reviewed rollback'
  end

  private

  def create_versions
    create_table TABLE do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.integer :revision, null: false
      t.bigint :source_audit_id, null: false
      t.bigint :actor_user_id
      t.string :actor_user_type
      t.jsonb :definition, null: false
      t.string :integrity_sha256, limit: 64, null: false
      t.datetime :created_at, null: false
    end
    add_index TABLE, [:id, :account_id], unique: true, name: 'cc_ending_reason_account_key'
    add_index TABLE, [:account_id, :revision], unique: true, name: 'cc_ending_reason_revision_key'
    add_index TABLE, :source_audit_id, unique: true, name: 'cc_ending_reason_audit_key'
    add_index TABLE, [:account_id, :created_at], name: 'cc_ending_reason_effective_time'
    add_check_constraint TABLE, "revision > 0 AND integrity_sha256 ~ '^[0-9a-f]{64}$'", name: 'cc_ending_reason_identity'
    add_check_constraint TABLE, "jsonb_typeof(definition) = 'object' AND octet_length(definition::text) <= 145000 " \
                                "AND (definition ->> 'version')::integer = revision " \
                                "AND jsonb_typeof(definition -> 'entries') = 'array' " \
                                'AND jsonb_array_length(definition -> \'entries\') <= 100', name: 'cc_ending_reason_definition'
  end

  def version_guard_sql
    <<~SQL.squish
      CREATE FUNCTION cc_ending_reason_version_guard() RETURNS trigger LANGUAGE plpgsql AS $guard$
      DECLARE source audits%ROWTYPE; last_revision integer; previous_definition jsonb;
      BEGIN
        IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM accounts WHERE id = OLD.account_id) THEN RETURN OLD; END IF;
        IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'Ending reason versions are immutable'; END IF;
        PERFORM 1 FROM accounts WHERE id = NEW.account_id FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'Ending reason account unavailable'; END IF;
        SELECT * INTO source FROM audits WHERE id = NEW.source_audit_id;
        IF NOT FOUND OR source.auditable_type IS DISTINCT FROM 'Account' OR source.auditable_id IS DISTINCT FROM NEW.account_id
          OR source.associated_type IS DISTINCT FROM 'Account' OR source.associated_id IS DISTINCT FROM NEW.account_id
          OR source.action IS DISTINCT FROM 'update' OR source.comment IS DISTINCT FROM 'jrc_contact_center_acw_policy_v1'
          OR source.audited_changes #> '{attributes,1,voice_reason_catalog}' IS DISTINCT FROM NEW.definition THEN
          RAISE EXCEPTION 'Ending reason audit provenance unavailable';
        END IF;
        SELECT revision, definition INTO last_revision, previous_definition
          FROM jrc_contact_center_ending_reason_versions WHERE account_id = NEW.account_id ORDER BY revision DESC LIMIT 1;
        IF NEW.revision <> COALESCE(last_revision, 0) + 1
          OR source.audited_changes #> '{attributes,0,voice_reason_catalog}' IS DISTINCT FROM previous_definition THEN
          RAISE EXCEPTION 'Ending reason revision sequence conflict';
        END IF;
        IF last_revision IS NOT NULL AND source.created_at < (SELECT MAX(created_at)
          FROM jrc_contact_center_ending_reason_versions WHERE account_id = NEW.account_id) THEN
          RAISE EXCEPTION 'Ending reason effective time conflict';
        END IF;
        NEW.created_at = source.created_at;
        NEW.actor_user_id = source.user_id;
        NEW.actor_user_type = source.user_type;
        NEW.integrity_sha256 = encode(sha256(convert_to(jsonb_build_object('account_id', NEW.account_id,
          'revision', NEW.revision, 'source_audit_id', NEW.source_audit_id, 'definition', NEW.definition)::text, 'UTF8')), 'hex');
        RETURN NEW;
      END $guard$;
      CREATE TRIGGER cc_ending_reason_version_guard BEFORE INSERT OR UPDATE OR DELETE
        ON jrc_contact_center_ending_reason_versions FOR EACH ROW EXECUTE FUNCTION cc_ending_reason_version_guard();
    SQL
  end

  def call_guard_sql
    <<~SQL.squish
      CREATE FUNCTION cc_ending_reason_call_guard() RETURNS trigger LANGUAGE plpgsql AS $guard$
      DECLARE configured jsonb; latest jsonb; selected_id bigint;
      BEGIN
        IF TG_OP = 'UPDATE' THEN
          IF NEW.ending_reason_version_id IS DISTINCT FROM OLD.ending_reason_version_id
            OR (OLD.ending_reason_version_id IS NOT NULL AND (NEW.account_id IS DISTINCT FROM OLD.account_id
              OR NEW.started_at IS DISTINCT FROM OLD.started_at)) THEN
            RAISE EXCEPTION 'Call ending reason origin is immutable';
          END IF;
          RETURN NEW;
        END IF;
        SELECT settings #> '{jrc_contact_center_acw,voice_reason_catalog}' INTO configured
          FROM accounts WHERE id = NEW.account_id FOR UPDATE;
        SELECT definition INTO latest FROM jrc_contact_center_ending_reason_versions
          WHERE account_id = NEW.account_id ORDER BY revision DESC LIMIT 1;
        IF configured IS DISTINCT FROM latest THEN RAISE EXCEPTION 'Ending reason ledger is not synchronized'; END IF;
        SELECT id INTO selected_id FROM jrc_contact_center_ending_reason_versions
          WHERE account_id = NEW.account_id AND created_at <= NEW.started_at ORDER BY created_at DESC, revision DESC LIMIT 1;
        IF NEW.ending_reason_version_id IS NOT NULL AND NEW.ending_reason_version_id IS DISTINCT FROM selected_id THEN
          RAISE EXCEPTION 'Call ending reason version cannot be supplied';
        END IF;
        NEW.ending_reason_version_id = selected_id;
        RETURN NEW;
      END $guard$;
      CREATE TRIGGER cc_ending_reason_call_guard BEFORE INSERT OR UPDATE ON jrc_contact_center_call_sessions
        FOR EACH ROW EXECUTE FUNCTION cc_ending_reason_call_guard();
    SQL
  end

  # Only exact, ordered native audit evidence can recover earlier catalogue revisions.
  # Missing evidence blocks migration; neither dates nor actors are invented.
  def backfill_proven_history!
    accounts = connection.select_rows("SELECT id, settings #> '{jrc_contact_center_acw,voice_reason_catalog}' FROM accounts " \
                                     "WHERE settings #> '{jrc_contact_center_acw,voice_reason_catalog}' IS NOT NULL ORDER BY id")
    accounts.each { |id, document| backfill_account!(id, json_document(document)) }
  end

  def backfill_account!(id, current)
    audits = connection.select_rows("SELECT id, audited_changes #> '{attributes,1,voice_reason_catalog}' FROM audits " \
                                   "WHERE auditable_type = 'Account' AND auditable_id = #{Integer(id)} " \
                                   "AND associated_type = 'Account' AND associated_id = #{Integer(id)} " \
                                   "AND comment = 'jrc_contact_center_acw_policy_v1' AND action = 'update' " \
                                   "AND audited_changes #> '{attributes,1,voice_reason_catalog}' IS DISTINCT FROM " \
                                   "audited_changes #> '{attributes,0,voice_reason_catalog}' ORDER BY id")
    audits.each do |audit_id, document|
      value = json_document(document)
      execute "INSERT INTO #{TABLE} (account_id, revision, source_audit_id, definition) " \
              "VALUES (#{Integer(id)}, #{Integer(value.fetch('version'))}, #{Integer(audit_id)}, #{connection.quote(value.to_json)}::jsonb)"
    end
    recovered = connection.select_value("SELECT definition FROM #{TABLE} WHERE account_id = #{Integer(id)} ORDER BY revision DESC LIMIT 1")
    proven = recovered && json_document(recovered) == current
    raise ActiveRecord::MigrationError, 'Unproven ending reason history; preserve source and investigate' unless proven
  end

  def json_document(value)
    value.is_a?(String) ? JSON.parse(value) : value
  end

  def verify_existing!
    columns = %w[id account_id revision source_audit_id actor_user_id actor_user_type definition integrity_sha256 created_at]
    valid = connection.columns(TABLE).map(&:name).sort == columns.sort && column_exists?(CALLS, :ending_reason_version_id, :bigint)
    valid &&= connection.foreign_keys(CALLS).any? { |key| key.name == 'cc_ending_reason_call_account_fk' && key.deferrable == :deferred }
    guards = connection.select_values("SELECT tgname FROM pg_trigger WHERE NOT tgisinternal AND tgname LIKE 'cc_ending_reason_%' " \
                                       "AND tgrelid IN (#{guard_relations})").sort
    expected = %w[cc_ending_reason_call_guard cc_ending_reason_origin_guard cc_ending_reason_qualification_guard cc_ending_reason_version_guard]
    valid &&= guards == expected
    valid &&= connection.table_comment(TABLE) == schema_receipt
    raise ActiveRecord::MigrationError, 'Unexpected ending reason ledger schema; review before reexecution' unless valid
  end

  def schema_receipt
    components = [connection.columns(TABLE).map { |column| [column.name, column.sql_type, column.null, column.default] }]
    components << connection.select_rows('SELECT pg_get_constraintdef(oid, true) FROM pg_constraint ' \
                                         "WHERE conrelid = '#{TABLE}'::regclass OR (conrelid = '#{CALLS}'::regclass " \
                                         "AND conname = 'cc_ending_reason_call_account_fk') ORDER BY conname")
    components << connection.select_rows('SELECT pg_get_triggerdef(oid, true), pg_get_functiondef(tgfoid) FROM pg_trigger ' \
                                         "WHERE NOT tgisinternal AND tgname LIKE 'cc_ending_reason_%' " \
                                         "AND tgrelid IN (#{guard_relations}) ORDER BY tgname")
    components << connection.indexes(TABLE).map { |index| [index.name, index.columns, index.unique] }.sort
    "jrc_cc_ending_reasons_v1:#{Digest::SHA256.hexdigest(components.to_json)}"
  end

  def guard_relations
    [TABLE, CALLS, :jrc_contact_center_agent_state_events, :jrc_contact_center_qualifications]
      .map { |name| "#{connection.quote(name.to_s)}::regclass" }.join(',')
  end
end
