# This fixture is exclusively for ephemeral GitHub Actions PostgreSQL services.
# It reproduces the pinned main migration ledger, not a production repair operation.
require 'digest'
require 'json'
require 'open3'
require 'tempfile'

base = 'd8a83b824b11cc68ddbbce7c79681f368051fb70'
databases = %w[jrc_rel_v2_candidate_test jrc_four_domains_schema_admission_test jrc_rel_sd_candidate_test jrc_jornada_candidate_test
               jrc_four_domains_schema_authority_test jrc_four_domains_schema_test jrc_ag_retention_native_test]
config = ActiveRecord::Base.connection_db_config
owned = ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
        ENV.fetch('GITHUB_RUN_ID', '').match?(/\A[0-9]+\z/) && ENV.fetch('JRC_AG_POSTGRES_SERVICE_ID', '').match?(/\A[a-f0-9]{12,64}\z/)
owned &&= Rails.env.test? && config.adapter == 'postgresql' && config.host == 'jrc-rel-v2-pg-20261101' && databases.include?(config.database)
raise 'Exclusive GitHub-hosted synthetic service required' unless owned

connection = ActiveRecord::Base.connection
marker_path = ENV.fetch('JRC_AG_FIXTURE_RECEIPT')
admission = JSON.parse(Rails.root.join('docs/jrc_consolidation/ag_historical_migration_admission_20261111.json').read)
raise 'Pinned main admission mismatch' unless admission.fetch('base_sha') == base
forward = JSON.parse(Rails.root.join('docs/jrc_consolidation/final_forward_migrations_20261112.json').read)
raise 'Forward migration base mismatch' unless forward.fetch('candidate_base') == '6195f7d21a0781cd5c5cf4d13bd73a497bb5a452'
historical_versions = admission.fetch('migrations').map { |entry| entry.fetch('version') }
forward_versions = forward.fetch('migrations').map do |entry|
  path = entry.fetch('path')
  version = entry.fetch('version')
  raise 'Unexpected forward migration path' unless path.match?(%r{\Adb/migrate/\d{14}_[a-z0-9_]+\.rb\z}) && File.basename(path).start_with?(version)
  raise 'Forward migration must follow audited history' unless version > historical_versions.max
  raise 'Forward migration content changed' unless Digest::SHA256.file(Rails.root.join(path)).hexdigest == entry.fetch('sha256')

  version
end
admitted_versions = (historical_versions + forward_versions).sort
raise 'Duplicate admitted migration version' unless admitted_versions.uniq == admitted_versions
case ARGV.fetch(0)
when 'load_main'
  raise 'Existing database contents must remain intact' unless connection.tables.empty?

  schema, status = Open3.capture2('git', 'show', "#{base}:db/schema.rb")
  raise 'Pinned main schema missing' unless status.success?

  paths, status = Open3.capture2('git', 'ls-tree', '-r', '--name-only', base, 'db/migrate')
  raise 'Pinned main migration inventory missing' unless status.success?

  version = schema.match(/define\(version: ([\d_]+)/)[1].delete('_')
  versions = paths.lines.filter_map { |line| line.match(%r{\Adb/migrate/(\d{14})_})&.[](1) }.select { |value| value <= version }
  raise 'Empty pinned main ledger' if versions.empty?

  Tempfile.create(['pinned_lab2_main_schema', '.rb']) do |file|
    file.write(schema)
    file.flush
    load file.path
  end
  # Schema.load otherwise assumes newly imported, backdated files already ran.
  # Reproduce only the versions actually shipped in main in this empty fixture.
  connection.execute('DELETE FROM schema_migrations')
  versions.uniq.each { |value| connection.execute("INSERT INTO schema_migrations(version) VALUES (#{connection.quote(value)})") }
  id = connection.select_value("INSERT INTO accounts(name, created_at, updated_at) VALUES ('SYNTHETIC A-G upgrade receipt', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING id")
  original_account_row = connection.select_one("SELECT * FROM accounts WHERE id = #{Integer(id)}")
  pending_versions = ActiveRecord::MigrationContext.new(Rails.root.join('db/migrate')).migrations.map(&:version).map(&:to_s) - versions
  raise 'Historical import pending ledger differs from reviewed inventory' unless pending_versions.sort == admitted_versions
  receipt = { account_id: id, digest: Digest::SHA256.hexdigest(JSON.generate(original_account_row)),
              main_sha: base, pending_versions: pending_versions.sort, before_versions: versions.sort }
  if ENV['JRC_AG_POPULATED_UPGRADE'] == '1'
    second_account = connection.select_value("INSERT INTO accounts(name, created_at, updated_at) VALUES ('SYNTHETIC separate scope', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING id")
    group_name = connection.quote('SYNTHETIC Grupo Á  ')
    company_ids = [id, id, second_account].map.with_index do |account_id, index|
      connection.select_value("INSERT INTO companies(name, account_id, economic_group, created_at, updated_at) VALUES " \
        "('SYNTHETIC upgrade company #{index}', #{Integer(account_id)}, #{group_name}, " \
        "'2026-01-10 10:00:00', '2026-01-11 11:00:00') RETURNING id")
    end
    user_id = connection.select_value("INSERT INTO users(name, uid, created_at, updated_at) VALUES ('SYNTHETIC upgrade user', 'synthetic-upgrade-#{ENV.fetch('GITHUB_RUN_ID')}', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING id")
    member_id = connection.select_value("INSERT INTO account_users(account_id, user_id, created_at, updated_at) VALUES (#{Integer(id)}, #{Integer(user_id)}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING id")
    contact_id = connection.select_value("INSERT INTO contacts(name, account_id, company_id, created_at, updated_at) VALUES ('SYNTHETIC upgrade contact', #{Integer(id)}, #{Integer(company_ids.first)}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING id")
    assignment_id = connection.select_value("INSERT INTO jrc_relationship_assignments(account_id, company_id, created_at, updated_at) VALUES (#{Integer(id)}, #{Integer(company_ids.first)}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING id")
    action_id = connection.select_value("INSERT INTO jrc_relationship_actions(account_id, assignment_id, kind, reason, source_key, created_at, updated_at) VALUES (#{Integer(id)}, #{Integer(assignment_id)}, 'contact', 'SYNTHETIC migration receipt', 'synthetic-upgrade-receipt', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING id")
    taxonomy_id = connection.select_value("INSERT INTO jrc_customer_taxonomies(account_id, kind, name, created_at, updated_at) VALUES (#{Integer(id)}, 'segment', 'SYNTHETIC upgrade segment', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) RETURNING id")
    subjects = company_ids.map { |value| ['companies', value] } +
               [['accounts', second_account], ['users', user_id], ['account_users', member_id],
                ['contacts', contact_id], ['jrc_relationship_assignments', assignment_id],
                ['jrc_relationship_actions', action_id], ['jrc_customer_taxonomies', taxonomy_id]]
    receipt[:preserved_rows] = subjects.map do |table, row_id|
      row = connection.select_one("SELECT * FROM #{connection.quote_table_name(table)} WHERE id = #{Integer(row_id)}")
      { table: table, id: row_id, columns: row.keys, digest: Digest::SHA256.hexdigest(JSON.generate(row)) }
    end
    receipt[:economic_groups] = connection.select_all("SELECT account_id, economic_group AS name, MIN(created_at) AS created_at, MAX(updated_at) AS updated_at FROM companies GROUP BY account_id, economic_group ORDER BY account_id, economic_group").to_a
    receipt[:defaults] = { member_id: member_id, contact_id: contact_id, action_id: action_id, taxonomy_id: taxonomy_id }
  end
  File.write(marker_path, JSON.generate(receipt))
when 'validate_constraints'
  # Main deliberately defers some validations on installed data. Prove every
  # constraint against our synthetic fixture instead of suppressing that gate.
  constraints = connection.select_all(<<~SQL)
    SELECT c.relname, k.conname FROM pg_constraint k
    JOIN pg_class c ON c.oid=k.conrelid
    WHERE k.connamespace='public'::regnamespace AND k.contype IN ('f','c') AND NOT k.convalidated
    ORDER BY c.relname, k.conname
  SQL
  constraints.each do |row|
    table = connection.quote_table_name(row.fetch('relname'))
    name = connection.quote_column_name(row.fetch('conname'))
    connection.execute("ALTER TABLE #{table} VALIDATE CONSTRAINT #{name}")
  end
  puts JSON.generate(synthetic_constraints_actually_validated: constraints.length)
when 'catalog'
  output = ENV.fetch('JRC_AG_CATALOG_OUTPUT')
  raise 'Owned temporary catalog output required' unless output.start_with?('/tmp/ag-') && !File.exist?(output)

  queries = {
    columns: "SELECT table_name, column_name, is_nullable, column_default, data_type, udt_name " \
             "FROM information_schema.columns WHERE table_schema='public' ORDER BY table_name, column_name",
    constraints: "SELECT c.relname, k.conname, k.contype, k.condeferrable, k.condeferred, k.convalidated, " \
                 "pg_get_constraintdef(k.oid) AS definition FROM pg_constraint k JOIN pg_class c ON c.oid=k.conrelid " \
                 "WHERE k.connamespace='public'::regnamespace AND k.contype IN ('f','c') ORDER BY c.relname, k.conname",
    indexes: "SELECT tablename, indexname, indexdef FROM pg_indexes WHERE schemaname='public' ORDER BY tablename, indexname",
    functions: "SELECT pg_get_functiondef(p.oid) AS definition FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace " \
               "WHERE n.nspname='public' AND p.prokind='f' AND NOT EXISTS (SELECT 1 FROM pg_depend d " \
               "WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e') " \
               "ORDER BY p.proname, pg_get_function_identity_arguments(p.oid)",
    triggers: "SELECT c.relname, t.tgname, pg_get_triggerdef(t.oid, true) AS definition FROM pg_trigger t " \
              "JOIN pg_class c ON c.oid=t.tgrelid WHERE c.relnamespace='public'::regnamespace AND NOT t.tgisinternal " \
              "ORDER BY c.relname, t.tgname"
  }
  catalog = queries.transform_values { |sql| connection.select_all(sql).to_a }
  raw_output = output.sub(/\.json\z/, '-raw.json')
  raise 'Prior raw catalog must remain intact' if raw_output == output || File.exist?(raw_output)

  raw_catalog = catalog.deep_dup
  File.write(raw_output, JSON.pretty_generate(raw_catalog))
  # PostgreSQL's own deparser moves varchar-array casts to individual members
  # when its output is parsed again. Reparse only comparison copies inside
  # rollback-only transactions; original objects/data and the raw catalog remain.
  catalog[:constraints].each_with_index do |row, index|
    next unless row.fetch('contype') == 'c'

    connection.transaction(requires_new: true) do
      name = "jrc_ag_catalog_check_#{index}"
      table = connection.quote_table_name(row.fetch('relname'))
      connection.execute("ALTER TABLE #{table} ADD CONSTRAINT #{connection.quote_column_name(name)} #{row.fetch('definition')}")
      row['definition'] = connection.select_value("SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname=#{connection.quote(name)} AND conrelid=#{connection.quote(row.fetch('relname'))}::regclass")
      raise ActiveRecord::Rollback
    end
  end
  catalog[:indexes].each_with_index do |row, index|
    next unless row.fetch('indexdef').include?(' WHERE ')

    original = row.fetch('indexname')
    original_token = Regexp.union(original, connection.quote_column_name(original))
    prefix = /\ACREATE (UNIQUE )?INDEX (#{original_token}) ON /
    raise 'Unexpected native index definition' unless prefix.match?(row.fetch('indexdef'))

    connection.transaction(requires_new: true) do
      name = "jrc_ag_catalog_index_#{index}"
      source = row.fetch('indexdef').sub(prefix) { "CREATE #{Regexp.last_match(1)}INDEX #{connection.quote_column_name(name)} ON " }
      connection.execute(source)
      normalized = connection.select_value("SELECT pg_get_indexdef(#{connection.quote(name)}::regclass)")
      temporary_prefix = /\ACREATE (UNIQUE )?INDEX #{Regexp.escape(name)} ON /
      raise 'Unexpected comparison index definition' unless temporary_prefix.match?(normalized)

      original_name = prefix.match(row.fetch('indexdef'))[2]
      row['indexdef'] = normalized.sub(temporary_prefix) { "CREATE #{Regexp.last_match(1)}INDEX #{original_name} ON " }
      raise ActiveRecord::Rollback
    end
  end
  unchanged = queries.transform_values { |sql| connection.select_all(sql).to_a }
  raise 'Comparison changed the original synthetic schema' unless unchanged == raw_catalog

  File.write(output, JSON.pretty_generate(catalog))
  puts JSON.generate(catalog_sha256: Digest::SHA256.file(output).hexdigest, groups: catalog.transform_values(&:length))
when 'verify'
  versions = connection.select_values('SELECT version FROM schema_migrations')
  expected = admitted_versions
  raise 'Cumulative migrations missing' unless (expected - versions).empty?

  pending = ActiveRecord::MigrationContext.new(Rails.root.join('db/migrate')).needs_migration?
  raise 'Pending migrations remain' if pending

  if File.exist?(marker_path)
    receipt = JSON.parse(File.read(marker_path))
    preserved_account_row = connection.select_one("SELECT * FROM accounts WHERE id = #{Integer(receipt.fetch('account_id'))}")
    raise 'Synthetic existing row changed during upgrade' unless Digest::SHA256.hexdigest(JSON.generate(preserved_account_row)) == receipt.fetch('digest')
    raise 'Reviewed pending versions did not all execute' unless (receipt.fetch('pending_versions') - versions).empty?
    receipt.fetch('preserved_rows', []).each do |subject|
      columns = subject.fetch('columns').map { |name| connection.quote_column_name(name) }.join(', ')
      row = connection.select_one("SELECT #{columns} FROM #{connection.quote_table_name(subject.fetch('table'))} WHERE id = #{Integer(subject.fetch('id'))}")
      raise 'Existing synthetic subject changed during upgrade' unless Digest::SHA256.hexdigest(JSON.generate(row)) == subject.fetch('digest')
    end
    if receipt.key?('economic_groups')
      groups = connection.select_all('SELECT account_id, name, created_at, updated_at FROM jrc_customer_economic_groups ORDER BY account_id, name').to_a
      raise 'Economic group scope, bytes or timestamps changed' unless JSON.generate(groups) == JSON.generate(receipt.fetch('economic_groups'))
      defaults = receipt.fetch('defaults')
      raise 'Contact defaults changed' unless connection.select_value("SELECT NOT company_primary AND company_contact_status = 'active' FROM contacts WHERE id = #{Integer(defaults.fetch('contact_id'))}")
      raise 'Action default changed' unless connection.select_value("SELECT customer_confirmation = 'pending' FROM jrc_relationship_actions WHERE id = #{Integer(defaults.fetch('action_id'))}")
      raise 'Segment defaults changed' unless connection.select_value("SELECT selection_mode = 'classification' AND criteria = '{\"match\":\"all\",\"rules\":[]}'::jsonb AND modules = '{}'::varchar[] FROM jrc_customer_taxonomies WHERE id = #{Integer(defaults.fetch('taxonomy_id'))}")
      raise 'Other module access changed' unless connection.select_value("SELECT jrc_relationship_withdrawn_at IS NULL AND jrc_relationship_eligibility_version = 0 AND NOT crm_enabled AND NOT jrc_projects_enabled FROM account_users WHERE id = #{Integer(defaults.fetch('member_id'))}")
    end
    proof = { main_sha: base, historical_versions: admission.fetch('migrations').select { |entry| entry.fetch('historical') }.map { |entry| entry.fetch('version') },
              required_versions: expected, pending_before: receipt.fetch('pending_versions'), missing_after: expected - versions,
              existing_versions_preserved: (receipt.fetch('before_versions') - versions).empty?,
              preserved_subjects: receipt.fetch('preserved_rows', []).length + 1, populated_upgrade: receipt.key?('defaults'),
              pending_after: pending }
    raise 'Existing migration ledger lost versions' unless proof[:existing_versions_preserved]
    proof_path = marker_path.sub(/\.json\z/, '-execution.json')
    File.write(proof_path, JSON.pretty_generate(proof))
    puts JSON.generate(proof)
  end
  functions = %w[jrc_bo_requirement_guard jrc_rel_history_receipt_guard jrc_bo_document_validity_guard jrc_rel_retention_immutable jrc_rel_management_guard]
  actual = connection.select_values("SELECT proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'")
  raise 'Native SQL guard functions missing' unless (functions - actual).empty?

  invalid = connection.select_value("SELECT count(*) FROM pg_constraint WHERE connamespace='public'::regnamespace AND contype IN ('f','c') AND NOT convalidated").to_i
  raise 'Unvalidated SQL constraints remain' unless invalid.zero?

  puts JSON.generate(database: config.database, verified_migrations: expected, guards_present: functions, unvalidated_constraints: invalid)
else
  raise 'Unknown synthetic fixture action'
end
