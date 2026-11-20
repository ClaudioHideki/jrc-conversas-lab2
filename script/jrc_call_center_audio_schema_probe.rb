# frozen_string_literal: true

# Schema metadata only, never uploaded bytes, account records or application credentials.
module JrcContactCenter::SyntheticAudioSchemaProbe
  def self.record(stage)
    require Rails.root.join('script/jrc_call_center_acw_form_schema_probe')
    owned = ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            JrcContactCenter::SyntheticAcwFormSchemaProbe.owned? && %w[fresh reload].include?(stage)
    raise 'Exclusive runner audio schema diagnostics required' unless owned

    require Rails.root.join('lib/jrc_contact_center/audio_file_schema_receipt')
    File.write("/tmp/call-center-audio-schema-#{stage}.json", JSON.pretty_generate(report(stage)))
  end

  def self.report(stage)
    connection = ActiveRecord::Base.connection
    receipt = JrcContactCenter::AudioFileSchemaReceipt.new(connection)
    components = { structure: structure(connection), constraints: receipt.send(:constraints),
                   functions: receipt.send(:functions), triggers: receipt.send(:triggers) }
    stored = JrcContactCenter::AudioFileSchemaReceipt::TABLES.index_with do |table|
      connection.table_comment(table)
    end
    { stage: stage, product_sha: ENV.fetch('GITHUB_SHA'), stored: stored, calculated: receipt.send(:token), components: components,
      component_hashes: components.transform_values { |value| Digest::SHA256.hexdigest(JSON.generate(value)) } }
  end

  def self.structure(connection)
    JrcContactCenter::AudioFileSchemaReceipt::TABLES.map do |table|
      columns = connection.columns(table).map { |row| [row.name, row.sql_type, row.null, row.default, row.default_function, row.collation] }
      indexes = connection.indexes(table).map { |row| [row.name, row.columns, row.unique, row.where] }.sort
      [table, columns, indexes]
    end
  end
end
