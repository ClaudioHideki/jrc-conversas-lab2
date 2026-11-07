# Explicit migration entrypoint for the exact owned synthetic candidate only.
require 'json'
require 'digest'

class JrcMasterSubjectSchemaGate
  VERSION = 20_261_107_010_000
  TABLES = %w[companies jrc_relationship_assignments jrc_relationship_batch_reviews jrc_relationship_batch_items].freeze

  def initialize
    @connection = ActiveRecord::Base.connection
    @report = { status: 'failed', build: false, production: false, application_servers_changed: false }
    @directory = ENV.fetch('JRC_SCHEMA_DIRECTORY')
    raise 'Owned schema artifact path required' unless @directory.match?(%r{\A/tmp/jrc_master_subject_schema_[0-9a-f]{12}\z}) &&
                                                       File.directory?(@directory)
  end

  def run
    validate!
    capture_before!
    migrate!
    verify_after!
    @report[:status] = 'passed'
  ensure
    @report[:database] = @connection.current_database
    File.write(File.join(@directory, 'result.json'), JSON.pretty_generate(@report))
    puts JSON.generate(@report)
  end

  private

  def capture_before!
    @report[:before] = snapshot
    @report[:parent_guard_before] = parent_guard
    @report[:versions_before] = versions
  end

  def migrate!
    @connection.execute("SET lock_timeout='3s'")
    @connection.execute("SET statement_timeout='30s'")
    @connection.migration_context.run(:up, VERSION)
    @connection.schema_cache.clear!
  end

  def verify_after!
    @report[:after] = snapshot
    raise 'Existing native business history changed' unless @report[:before] == @report[:after]
    raise 'Original review snapshot guard changed' unless @report[:parent_guard_before] == parent_guard
    raise 'Unexpected migration history' unless versions == (@report[:versions_before] + [VERSION.to_s]).sort
  end

  def validate!
    validate_environment!
    raise 'No surrounding transaction allowed' if @connection.transaction_open?

    pending = @connection.migration_context.migrations.map(&:version).map(&:to_s) - versions
    raise 'Only the explicit additive target may be pending' unless pending == [VERSION.to_s]
  end

  def validate_environment!
    raise 'Test environment required' unless Rails.env.test?
    raise 'Exact owned test database required' unless @connection.current_database == 'jrc_rel_v2_candidate_test' &&
                                                      ENV.fetch('POSTGRES_DATABASE') == 'jrc_rel_v2_candidate_test'

    host = ActiveRecord::Base.connection_db_config.configuration_hash[:host]
    raise 'Exact owned PostgreSQL host required' unless host == 'jrc-rel-v2-pg-20261101'
  end

  def versions
    @connection.select_values('SELECT version FROM schema_migrations ORDER BY version')
  end

  def parent_guard
    Digest::SHA256.hexdigest(@connection.select_value("SELECT pg_get_functiondef('rel_batch_review_guard()'::regprocedure)"))
  end

  def snapshot
    TABLES.to_h do |table|
      # New nullable column is metadata only; compare every original item field.
      expression = table == 'jrc_relationship_batch_items' ? "to_jsonb(t)-'company_id'" : 'to_jsonb(t)'
      sql = "SELECT count(*) AS count, md5(COALESCE(string_agg((#{expression})::text, '|' ORDER BY id), '')) AS digest " \
            "FROM #{table} t"
      result = @connection.select_one(sql)
      [table, result]
    end
  end
end

JrcMasterSubjectSchemaGate.new.run
