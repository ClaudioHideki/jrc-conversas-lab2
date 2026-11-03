# Apply pending SQL migrations after schema:load without rewriting schema.rb.
# This helper is exclusively for disposable test databases, never production.
require 'digest'

database = ActiveRecord::Base.connection_db_config.database
raise 'Named disposable test database required' unless Rails.env.test? && database.end_with?('_test')

schema_path = Rails.root.join('db/schema.rb')
original_digest = Digest::SHA256.file(schema_path).hexdigest
context = ActiveRecord::MigrationContext.new(Rails.root.join('db/migrate'))
context.migrate
raise 'Pending migrations remain' if context.needs_migration?
raise 'Schema source was modified' unless Digest::SHA256.file(schema_path).hexdigest == original_digest

connection = ActiveRecord::Base.connection
guards = connection.select_values(<<~SQL.squish)
  SELECT tgname FROM pg_trigger
  WHERE tgrelid = 'jrc_migration_media_objects'::regclass AND NOT tgisinternal
SQL
expected_guards = %w[jrc_migration_media_owner_rows jrc_migration_media_owner_truncate]
raise 'Media ownership SQL guards missing' unless (expected_guards - guards).empty?

constraints = connection.check_constraints(:jrc_migration_media_objects).map(&:name)
raise 'Destination identity guard missing' unless constraints.include?('jrc_migration_media_destination_identity')

puts "Candidate test schema verified: version=#{context.current_version}, ownership_guards=#{guards.size}, source_unchanged=true"
