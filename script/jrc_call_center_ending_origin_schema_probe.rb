# frozen_string_literal: true

# Prepared, not executed. Schema metadata only, guarded by the actual exclusive
# GitHub-hosted PostgreSQL/Redis endpoints and the expected phase database.
module JrcContactCenter::SyntheticEndingOriginSchemaProbe
  DATABASES = {
    'fresh' => 'jrc_sd_bc_portal_concurrency_20261025_test',
    'reload' => 'jrc_cc_access_schema_reload_synthetic',
    'populated' => 'jrc_cc_ending_origin_upgrade_synthetic'
  }.freeze

  def self.record(stage)
    config = ApplicationRecord.connection_db_config
    owned = ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' && Rails.env.test? &&
            config.configuration_hash[:host] == '127.0.0.1' && config.database == DATABASES.fetch(stage) &&
            ApplicationRecord.connection.current_database == config.database && ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15'
    raise 'Exclusive ending origin schema diagnostics runner required' unless owned

    require Rails.root.join('lib/jrc_contact_center/ending_execution_origin_schema_receipt')
    File.write("/tmp/call-center-ending-origin-schema-#{stage}.json", JSON.pretty_generate(report(stage)))
    JrcContactCenter::EndingExecutionOriginSchemaReceipt.new(ApplicationRecord.connection).verify!
  end

  def self.report(stage)
    connection = ApplicationRecord.connection
    receipt = JrcContactCenter::EndingExecutionOriginSchemaReceipt.new(connection)
    components = %i[structure constraints functions triggers].index_with { |name| receipt.send(name) }
    stored = [receipt.class::ORIGINS, receipt.class::COMPLETIONS].index_with { |table| connection.table_comment(table) }
    { stage: stage, product_sha: ENV.fetch('GITHUB_SHA'), stored: stored, calculated: receipt.send(:token), components: components,
      component_hashes: components.transform_values { |value| Digest::SHA256.hexdigest(JSON.generate(value)) } }
  end
end
