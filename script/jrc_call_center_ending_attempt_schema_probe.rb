# frozen_string_literal: true

require Rails.root.join('script/jrc_call_center_ending_origin_schema_probe')

# Disposable schema evidence only. An unverified early diagnostic is explicitly
# preserved before the exact check; it can never satisfy the acceptance gate.
module JrcContactCenter::SyntheticEndingAttemptSchemaProbe
  DATABASES = JrcContactCenter::SyntheticEndingOriginSchemaProbe::DATABASES.merge(
    'populated' => 'jrc_cc_ending_attempt_upgrade_synthetic'
  ).freeze

  def self.record(stage)
    guard!(stage)
    require Rails.root.join('lib/jrc_contact_center/ending_action_attempt_schema_receipt')
    receipt = JrcContactCenter::EndingActionAttemptSchemaReceipt.new(ApplicationRecord.connection)
    proof = report(stage, receipt)
    write_report(stage, proof.merge(verified: false))
    receipt.verify!
    raise 'Installation cannot create pending attempts or outcomes' unless proof[:attempt_count].zero? && proof[:outcome_count].zero?

    write_report(stage, proof.merge(verified: true))
  end

  def self.guard!(stage)
    config = ApplicationRecord.connection_db_config
    owned = JrcContactCenter::SyntheticEndingOriginSchemaProbe.runner_owned? && config.configuration_hash[:host] == '127.0.0.1' &&
            config.database == DATABASES.fetch(stage) && ApplicationRecord.connection.current_database == config.database
    raise 'Exclusive ending attempt schema diagnostics required' unless owned
  end

  def self.write_report(stage, proof)
    File.write("/tmp/call-center-ending-attempt-schema-#{stage}.json", JSON.pretty_generate(proof))
  end

  def self.report(stage, receipt)
    components = %i[structure constraints functions triggers].index_with { |name| receipt.send(name) }
    comments = receipt.class::TABLES.index_with { |table| ApplicationRecord.connection.table_comment(table) }
    calculated = receipt.send(:token)
    { stage: stage, product_sha: ENV.fetch('GITHUB_SHA'), stored: comments, calculated: calculated, components: components,
      component_hashes: components.transform_values { |value| Digest::SHA256.hexdigest(JSON.generate(value)) },
      attempt_count: JrcContactCenter::EndingActionAttempt.count, outcome_count: JrcContactCenter::EndingActionAttemptOutcome.count,
      verification_checks: { structure: receipt.send(:valid_structure?), references: receipt.send(:valid_references?),
                             fingerprint: comments.values.all?(calculated) } }
  end
end
