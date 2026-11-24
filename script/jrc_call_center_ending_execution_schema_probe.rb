# frozen_string_literal: true

# PRIVATE CANDIDATE. Schema metadata only, never a success or runtime acceptance.
require Rails.root.join('script/jrc_call_center_ending_origin_schema_probe')

module JrcContactCenter::SyntheticEndingExecutionSchemaProbe
  DATABASES = JrcContactCenter::SyntheticEndingOriginSchemaProbe::DATABASES.merge(
    'populated' => 'jrc_cc_ending_success_upgrade_synthetic'
  ).freeze

  def self.record(stage)
    config = ApplicationRecord.connection_db_config
    owned = JrcContactCenter::SyntheticEndingOriginSchemaProbe.runner_owned? && connection_owned?(config, stage)
    raise 'Exclusive ending success schema diagnostics required' unless owned

    require Rails.root.join('lib/jrc_contact_center/ending_action_execution_schema_receipt')
    receipt = JrcContactCenter::EndingActionExecutionSchemaReceipt.new(ApplicationRecord.connection)
    proof = report(stage, receipt)
    write_report(stage, proof.merge(verified: false))
    receipt.verify!
    raise 'Installation cannot execute an existing attendance' unless proof[:success_count].zero?

    write_report(stage, proof.merge(verified: true))
  end

  def self.write_report(stage, proof)
    File.write("/tmp/call-center-ending-success-schema-#{stage}.json", JSON.pretty_generate(proof))
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
      success_count: JrcContactCenter::EndingActionExecution.count,
      verification_checks: { structure: receipt.send(:valid_structure?), references: receipt.send(:valid_references?),
                             fingerprint: ApplicationRecord.connection.table_comment(receipt.class::TABLE) == receipt.send(:token) } }
  end
end
