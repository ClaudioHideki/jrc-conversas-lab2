# Opt-in schema regression, never a production migration or data export.
# HISTORY_SCHEMA_TEST=true RAILS_ENV=test bundle exec rails runner script/ci/jrc_history_schema_load.rb
require 'securerandom'
require 'json'

original = ActiveRecord::Base.connection_db_config.configuration_hash
unless ENV['HISTORY_SCHEMA_TEST'] == 'true' && Rails.env.test? && original.fetch(:database).start_with?('jrc_history_', 'jrc_test_')
  abort 'Only an explicitly enabled disposable history test database is permitted'
end
database = "jrc_history_schema_#{SecureRandom.hex(6)}"
raise 'Invalid test database name' unless /\Ajrc_history_schema_[a-f0-9]{12}\z/.match?(database)

ActiveRecord::Base.connection.execute("CREATE DATABASE #{database}")
begin
  ActiveRecord::Base.establish_connection(original.merge(database: database))
  load Rails.root.join('db/schema.rb')
  connection = ActiveRecord::Base.connection
  raise 'Wrong schema test target' unless connection.select_value('SELECT current_database()') == database

  %w[jrc_broker_history_media jrc_broker_history_visibilities jrc_broker_history_receipts].each do |table|
    raise "Missing #{table}" unless connection.table_exists?(table)
  end
  raise 'Missing original credential fence' unless connection.column_exists?(:jrc_broker_history_media, :access_token_sha256)

  trigger = connection.select_value("SELECT count(*) FROM pg_trigger WHERE tgname='jrc_history_visibility_revoke'")
  raise 'Missing history revocation fence' unless trigger.to_i == 1

  puts({ fresh_schema: 'PASS', media_columns: connection.columns(:jrc_broker_history_media).length,
         visibility_revocation_trigger: trigger.to_i, data_exported: false }.to_json)
ensure
  ActiveRecord::Base.connection_pool.disconnect!
  ActiveRecord::Base.establish_connection(original)
  ActiveRecord::Base.connection.execute("DROP DATABASE #{database}")
end
