# Exclusive synthetic bootstrap using Rails' normal migration-task loading order.
require 'json'
require 'digest'
require 'pg'
require 'rake'

raise 'Production-like synthetic runtime required' unless ENV.fetch('RAILS_ENV') == 'production'
raise 'Wrong synthetic database' unless ENV.fetch('POSTGRES_DATABASE') == 'jrc_runtime_image_test'
host = ENV.fetch('POSTGRES_HOST')
native = ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' && host == '127.0.0.1'
image = host.match?(/\Ajrc-runtime-\d+-1-pg\z/) && ENV.fetch('RUNTIME_SMOKE_NONCE', '').match?(/\A[0-9a-f]{32}\z/)
raise 'Exclusive owned database host required' unless native || image
PG.connect(host: host, port: ENV.fetch('POSTGRES_PORT', '5432'),
           dbname: ENV.fetch('POSTGRES_DATABASE'), user: ENV.fetch('POSTGRES_USERNAME'),
           password: ENV.fetch('POSTGRES_PASSWORD')) do |connection|
  raise 'Existing application schema refused' unless connection.exec("SELECT to_regclass('public.accounts')").getvalue(0, 0).nil?
end

schema = File.join(Dir.pwd, 'db/schema.rb')
before = Digest::SHA256.file(schema).hexdigest
Rake.application.init('rake', ['db:migrate'])
Rake.application.load_rakefile
Rails.application.config.active_record.dump_schema_after_migration = false
Rake.application.top_level
raise 'Schema export must remain disabled' unless ActiveRecord.dump_schema_after_migration == false
raise 'Tracked schema changed' unless Digest::SHA256.file(schema).hexdigest == before
connection = ActiveRecord::Base.connection
versions = connection.select_values('SELECT version FROM schema_migrations')
required = %w[20261111170000 20261112120000]
raise 'Additional history migrations missing' unless (required - versions).empty?
raise 'Migrations remain pending' if connection.migration_context.needs_migration?
trigger = connection.select_value("SELECT count(*) FROM pg_trigger WHERE tgname='jrc_history_visibility_revoke' AND NOT tgisinternal")
raise 'Historical visibility trigger missing' unless trigger.to_i == 1
puts JSON.generate(passed: true, database: 'exclusive_synthetic', additional_versions: required,
                   history_visibility_trigger: true, pending: false, schema_exported: false,
                   tracked_schema_preserved: true, backup_or_restore_executed: false)
