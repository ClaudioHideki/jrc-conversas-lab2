# frozen_string_literal: true

require Rails.root.join('script/jrc_call_center_ending_origin_schema_probe')

# Reuse the disposable runner guard and name every owned database explicitly.
# A schema receipt never proves activation or execution.
module JrcContactCenter::SyntheticEndingReadinessSchemaProbe
  DATABASES = JrcContactCenter::SyntheticEndingOriginSchemaProbe::DATABASES.merge(
    'populated' => 'jrc_cc_ending_readiness_upgrade_synthetic'
  ).freeze

  def self.record(stage)
    config = ApplicationRecord.connection_db_config
    owned = JrcContactCenter::SyntheticEndingOriginSchemaProbe.runner_owned? && connection_owned?(config, stage)
    raise 'Exclusive ending readiness schema diagnostics required' unless owned

    require Rails.root.join('lib/jrc_contact_center/ending_action_readiness_schema_receipt')
    receipt = JrcContactCenter::EndingActionReadinessSchemaReceipt.new(ApplicationRecord.connection)
    receipt.verify!
    proof = report(stage, receipt)
    raise 'Installation cannot arm an existing rule' unless proof[:readiness_count].zero?

    File.write("/tmp/call-center-ending-readiness-schema-#{stage}.json", JSON.pretty_generate(proof))
  end

  def self.connection_owned?(config, stage)
    config.configuration_hash[:host] == '127.0.0.1' && config.database == DATABASES.fetch(stage) &&
      ApplicationRecord.connection.current_database == config.database
  end

  def self.report(stage, receipt)
    components = %i[structure constraints functions triggers].index_with { |name| receipt.send(name) }
    { stage: stage, product_sha: ENV.fetch('GITHUB_SHA'), stored: ApplicationRecord.connection.table_comment(receipt.class::TABLE),
      calculated: receipt.send(:token), components: components,
      component_hashes: components.transform_values { |value| Digest::SHA256.hexdigest(JSON.generate(value)) },
      readiness_count: JrcContactCenter::EndingActionReadiness.count }
  end
end
