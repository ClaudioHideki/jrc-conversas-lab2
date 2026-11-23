# frozen_string_literal: true

# Unapplied WIP. Reports metadata only in the already exclusive disposable schema databases.
module JrcContactCenter::SyntheticEndingVersionSchemaProbe
  def self.record(stage)
    require Rails.root.join('script/jrc_call_center_acw_form_schema_probe')
    owned = ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            JrcContactCenter::SyntheticAcwFormSchemaProbe.owned? && %w[fresh reload].include?(stage)
    raise 'Exclusive runner ending action version diagnostics required' unless owned

    require Rails.root.join('lib/jrc_contact_center/ending_action_version_schema_receipt')
    File.write("/tmp/call-center-ending-version-schema-#{stage}.json", JSON.pretty_generate(report(stage)))
    JrcContactCenter::EndingActionVersionSchemaReceipt.new(ActiveRecord::Base.connection).verify!
  end

  def self.report(stage)
    connection = ActiveRecord::Base.connection
    receipt = JrcContactCenter::EndingActionVersionSchemaReceipt.new(connection)
    components = %i[structure constraints functions triggers].index_with { |name| receipt.send(name) }
    { stage: stage, product_sha: ENV.fetch('GITHUB_SHA'), stored: { receipt.class::TABLE => connection.table_comment(receipt.class::TABLE) },
      calculated: receipt.send(:token), components: components,
      component_hashes: components.transform_values { |value| Digest::SHA256.hexdigest(JSON.generate(value)) } }
  end
end
