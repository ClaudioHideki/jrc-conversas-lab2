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
  row = connection.select_one("SELECT * FROM accounts WHERE id = #{Integer(id)}")
  File.write(marker_path, JSON.generate(account_id: id, digest: Digest::SHA256.hexdigest(JSON.generate(row)), main_sha: base))
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
  File.write(output, JSON.pretty_generate(catalog))
  puts JSON.generate(catalog_sha256: Digest::SHA256.file(output).hexdigest, groups: catalog.transform_values(&:length))
when 'verify'
  versions = connection.select_values('SELECT version FROM schema_migrations')
  expected = %w[20261109190000 20261109191000 20261109200000 20261109210000 20261109211000 20261109212000 20261110190000]
  raise 'Cumulative migrations missing' unless (expected - versions).empty?

  pending = ActiveRecord::MigrationContext.new(Rails.root.join('db/migrate')).needs_migration?
  raise 'Pending migrations remain' if pending

  if File.exist?(marker_path)
    receipt = JSON.parse(File.read(marker_path))
    row = connection.select_one("SELECT * FROM accounts WHERE id = #{Integer(receipt.fetch('account_id'))}")
    raise 'Synthetic existing row changed during upgrade' unless Digest::SHA256.hexdigest(JSON.generate(row)) == receipt.fetch('digest')
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
