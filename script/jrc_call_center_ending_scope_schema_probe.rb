# frozen_string_literal: true

# Metadata only in the existing exclusive disposable databases, never a production schema change.
module JrcContactCenter::SyntheticEndingScopeSchemaProbe
  def self.record(stage)
    require Rails.root.join('script/jrc_call_center_acw_form_schema_probe')
    owned = ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            JrcContactCenter::SyntheticAcwFormSchemaProbe.owned? && %w[fresh reload].include?(stage)
    raise 'Exclusive runner ending action scope diagnostics required' unless owned

    require Rails.root.join('lib/jrc_contact_center/ending_action_scope_schema_receipt')
    File.write("/tmp/call-center-ending-scope-schema-#{stage}.json", JSON.pretty_generate(report(stage)))
  end

  def self.report(stage)
    connection = ActiveRecord::Base.connection
    receipt = JrcContactCenter::EndingActionScopeSchemaReceipt.new(connection)
    receipt.verify!
    components = %i[structure constraints functions triggers].index_with { |name| receipt.send(name) }
    { stage: stage, product_sha: ENV.fetch('GITHUB_SHA'), stored: { receipt.class::TABLE => connection.table_comment(receipt.class::TABLE) },
      calculated: receipt.send(:token), components: components,
      component_hashes: components.transform_values { |value| Digest::SHA256.hexdigest(JSON.generate(value)) } }
  end
end
