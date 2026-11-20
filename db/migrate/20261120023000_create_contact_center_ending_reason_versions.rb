# frozen_string_literal: true

# New calls pin the existing account catalogue; old calls deliberately remain unpinned.
class CreateContactCenterEndingReasonVersions < ActiveRecord::Migration[7.1]
  TABLE = :jrc_contact_center_ending_reason_versions
  CALLS = :jrc_contact_center_call_sessions
  ORIGIN_SQL_SHA256 = 'c0dca8b84c8c4b02d78ed07be4e23bb253f0d64994dccc232ba879941ef35bf8'
  CATALOG_SQL_SHA256 = 'c729952430c681932c3ae7686880cdee96d532f183d2fada33181e0a6ee5445f'
  SQL_SOURCES = {
    'lib/jrc_contact_center/ending_reason_origin_sql.rb' => ORIGIN_SQL_SHA256,
    'lib/jrc_contact_center/ending_reason_catalog_sql.rb' => CATALOG_SQL_SHA256
  }.freeze

  def up
    matches = SQL_SOURCES.all? do |path, expected|
      Digest::SHA256.file(Rails.root.join(path)).hexdigest == expected
    end
    raise ActiveRecord::MigrationError, 'Ending reason SQL source changed; review before migration' unless matches

    return verify_existing! if table_exists?(TABLE)

    create_versions
    execute JrcContactCenter::EndingReasonCatalogSql.new.version_guard
    backfill_proven_history!
    create_call_reference
    execute JrcContactCenter::EndingReasonCatalogSql.new.call_guard
    execute JrcContactCenter::EndingReasonOriginSql.new.call
    change_table_comment TABLE, schema_receipt
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Ending reason call history requires a separately reviewed rollback'
  end

  private

  def create_call_reference
    add_column CALLS, :ending_reason_version_id, :bigint
    add_column CALLS, :ending_reason_captured_started_at, :datetime
    add_check_constraint CALLS, '(ending_reason_version_id IS NULL AND ending_reason_captured_started_at IS NULL) OR ' \
                                '(ending_reason_version_id IS NOT NULL AND ending_reason_captured_started_at IS NOT NULL)',
                         name: 'cc_ending_reason_call_capture'
    add_foreign_key CALLS, TABLE, column: [:ending_reason_version_id, :account_id], primary_key: [:id, :account_id],
                                  deferrable: :deferred, name: 'cc_ending_reason_call_account_fk'
    add_index CALLS, :ending_reason_version_id, name: 'cc_ending_reason_call_version'
  end

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
    create_version_constraints
  end

  def create_version_constraints
    add_check_constraint TABLE, "revision > 0 AND integrity_sha256 ~ '^[0-9a-f]{64}$'", name: 'cc_ending_reason_identity'
    add_check_constraint TABLE, "jsonb_typeof(definition) = 'object' AND octet_length(definition::text) <= 145000 " \
                                "AND definition ? 'version' AND definition ? 'entries' " \
                                "AND jsonb_typeof(definition -> 'version') = 'number' " \
                                "AND (definition ->> 'version')::integer = revision " \
                                "AND jsonb_typeof(definition -> 'entries') = 'array' " \
                                'AND jsonb_array_length(definition -> \'entries\') <= 100', name: 'cc_ending_reason_definition'
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
    valid = connection.columns(TABLE).map(&:name).sort == columns.sort
    valid &&= call_reference?
    guards = connection.select_values("SELECT tgname FROM pg_trigger WHERE NOT tgisinternal AND tgname LIKE 'cc_ending_reason_%' " \
                                      "AND tgrelid IN (#{guard_relations})").sort
    expected = %w[cc_ending_reason_call_guard cc_ending_reason_origin_guard cc_ending_reason_qualification_guard cc_ending_reason_version_guard]
    valid &&= guards == expected
    valid &&= connection.table_comment(TABLE) == schema_receipt
    raise ActiveRecord::MigrationError, 'Unexpected ending reason ledger schema; review before reexecution' unless valid
  end

  def call_reference?
    return false unless call_columns?

    connection.foreign_keys(CALLS).any? { |key| key.name == 'cc_ending_reason_call_account_fk' && key.deferrable == :deferred }
  end

  def call_capture_columns
    connection.columns(CALLS).select { |column| %w[ending_reason_version_id ending_reason_captured_started_at].include?(column.name) }
  end

  def call_columns?
    columns = call_capture_columns.index_by(&:name)
    identity = columns['ending_reason_version_id']
    started = columns['ending_reason_captured_started_at']
    return false unless identity && started

    identity.sql_type == 'bigint' && identity.null && started.type == :datetime && started.null
  end

  def schema_receipt
    components = column_receipt
    components << connection.select_rows('SELECT pg_get_constraintdef(oid, true) FROM pg_constraint ' \
                                         "WHERE conrelid = '#{TABLE}'::regclass OR (conrelid = '#{CALLS}'::regclass " \
                                         "AND conname IN ('cc_ending_reason_call_account_fk', 'cc_ending_reason_call_capture')) ORDER BY conname")
    components << connection.select_rows('SELECT pg_get_triggerdef(oid, true), pg_get_functiondef(tgfoid) FROM pg_trigger ' \
                                         "WHERE NOT tgisinternal AND tgname LIKE 'cc_ending_reason_%' " \
                                         "AND tgrelid IN (#{guard_relations}) ORDER BY tgname")
    components << connection.indexes(TABLE).map { |index| [index.name, index.columns, index.unique] }.sort
    "jrc_cc_ending_reasons_v1:#{Digest::SHA256.hexdigest(components.to_json)}"
  end

  def column_receipt
    [connection.columns(TABLE), call_capture_columns].map do |columns|
      columns.map { |column| [column.name, column.sql_type, column.null, column.default] }
    end
  end

  def guard_relations
    [TABLE, CALLS, :jrc_contact_center_agent_state_events, :jrc_contact_center_qualifications]
      .map { |name| "#{connection.quote(name.to_s)}::regclass" }.join(',')
  end
end
