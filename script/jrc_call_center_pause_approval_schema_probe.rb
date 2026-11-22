# frozen_string_literal: true

# Read-only schema metadata only; no actor payload, justification, account records or credentials.
module JrcContactCenter::SyntheticPauseApprovalSchemaProbe
  def self.record(stage)
    require Rails.root.join('script/jrc_call_center_acw_form_schema_probe')
    owned = ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            JrcContactCenter::SyntheticAcwFormSchemaProbe.owned? && %w[fresh reload].include?(stage)
    raise 'Exclusive runner pause approval schema diagnostics required' unless owned

    require Rails.root.join('lib/jrc_contact_center/pause_approval_schema_receipt')
    File.write("/tmp/call-center-pause-approval-schema-#{stage}.json", JSON.pretty_generate(report(stage)))
  end

  def self.report(stage)
    connection = ActiveRecord::Base.connection
    receipt = JrcContactCenter::PauseApprovalSchemaReceipt.new(connection)
    components = { structure: structure(connection), constraints: receipt.send(:constraints),
                   functions: receipt.send(:functions), triggers: receipt.send(:triggers) }
    stored = JrcContactCenter::PauseApprovalSchemaReceipt::TABLES.index_with do |table|
      connection.table_comment(table)
    end
    { stage: stage, product_sha: ENV.fetch('GITHUB_SHA'), stored: stored, calculated: receipt.send(:token), components: components,
      component_hashes: components.transform_values { |value| Digest::SHA256.hexdigest(JSON.generate(value)) } }
  end

  def self.structure(connection)
    JrcContactCenter::PauseApprovalSchemaReceipt::TABLES.map do |table|
      columns = connection.columns(table).map { |row| [row.name, row.sql_type, row.null, row.default, row.default_function, row.collation] }
      indexes = connection.indexes(table).map { |row| [row.name, row.columns, row.unique, row.where] }.sort
      [table, columns, indexes]
    end
  end
end
