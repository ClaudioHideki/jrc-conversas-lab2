# frozen_string_literal: true

require 'json'
require 'digest'
require Rails.root.join('lib/jrc_contact_center/ending_destination_schema_receipt')

# Owned fresh/reload/populated diagnostics only. Verification never installs,
# restamps, repairs or activates an existing unknown history structure.
module JrcContactCenter::SyntheticTypedDestinationSchemaProbe
  DATABASES = {
    'fresh' => 'jrc_sd_bc_portal_concurrency_20261025_test',
    'reload' => 'jrc_cc_access_schema_reload_synthetic',
    'populated' => 'jrc_cc_typed_destination_upgrade_synthetic'
  }.freeze

  def self.record(stage)
    guard!(stage)
    receipt = JrcContactCenter::EndingDestinationSchemaReceipt.new(ApplicationRecord.connection)
    proof = report(stage, receipt)
    write(stage, proof.merge(verified: false))
    receipt.verify!
    raise 'Installation cannot fabricate typed history' unless proof.fetch(:table_counts).values.all?(&:zero?)

    write(stage, proof.merge(verified: true))
  end

  def self.guard!(stage)
    config = ApplicationRecord.connection_db_config
    owned = runner_owned? && config.configuration_hash[:host] == '127.0.0.1' &&
            config.database == DATABASES.fetch(stage) && ApplicationRecord.connection.current_database == config.database &&
            !ApplicationRecord.connection.transaction_open?
    raise 'Exclusive typed ending schema diagnostics required' unless owned
  end

  def self.runner_owned?
    Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
      ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15'
  end

  def self.report(stage, receipt)
    components = %i[structure constraints functions triggers].index_with { |name| receipt.send(name) }
    tables = receipt.class::TABLES
    counts = tables.index_with { |table| ApplicationRecord.connection.select_value("SELECT count(*) FROM #{table}").to_i }
    { stage: stage, product_sha: ENV.fetch('GITHUB_SHA'), table_counts: counts,
      stored: tables.index_with { |table| ApplicationRecord.connection.table_comment(table) }, calculated: receipt.send(:token),
      components: components, component_hashes: components.transform_values { |value| Digest::SHA256.hexdigest(JSON.generate(value)) } }
  end

  def self.write(stage, proof)
    File.write("/tmp/call-center-typed-destination-schema-#{stage}.json", JSON.pretty_generate(proof))
  end
end
