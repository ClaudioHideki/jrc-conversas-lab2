# frozen_string_literal: true

require 'json'
require 'digest'
require Rails.root.join('lib/jrc_contact_center/quality_review_schema_receipt')

# Read-only PostgreSQL evidence on the same three disposable stages as native ending ledgers.
module JrcContactCenter::SyntheticQualitySchemaProbe
  DATABASES = {
    'fresh' => 'jrc_sd_bc_portal_concurrency_20261025_test', 'reload' => 'jrc_cc_access_schema_reload_synthetic',
    'populated' => 'jrc_cc_quality_review_upgrade_synthetic'
  }.freeze

  def self.record(stage)
    guard!(stage)
    receipt = JrcContactCenter::QualityReviewSchemaReceipt.new(ApplicationRecord.connection)
    components = %i[structure constraints functions triggers].index_with { |name| receipt.send(name) }
    proof = { stage: stage, product_sha: ENV.fetch('GITHUB_SHA'), table_count: JrcContactCenter::QualityReviewRevision.count,
              stored: ApplicationRecord.connection.table_comment(receipt.class::TABLE), calculated: receipt.send(:token),
              components: components, component_hashes: components.transform_values { |value| Digest::SHA256.hexdigest(JSON.generate(value)) } }
    receipt.verify!
    raise 'Installation cannot manufacture human reviews' unless proof.fetch(:table_count).zero?

    File.write("/tmp/call-center-quality-schema-#{stage}.json", JSON.pretty_generate(proof.merge(verified: true)))
  end

  def self.guard!(stage)
    config = ApplicationRecord.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            ENV['REDIS_URL'] == 'redis://127.0.0.1:6379/15' && config.configuration_hash[:host] == '127.0.0.1' &&
            config.database == DATABASES.fetch(stage) && ApplicationRecord.connection.current_database == config.database &&
            !ApplicationRecord.connection.transaction_open?
    raise 'Exclusive disposable quality schema diagnostics required' unless owned
  end
end
