# Read-only metadata diagnostics for the explicitly owned disposable databases.
module JrcContactCenter::SyntheticAcwFormSchemaProbe
  def self.record(stage)
    return unless ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted'

    raise 'Owned synthetic ACW schema diagnostics required' unless owned? && %w[fresh reload rspec].include?(stage)

    require Rails.root.join('db/migrate/20261119190000_create_contact_center_acw_forms')
    suffix = stage == 'rspec' ? 'rspec-context' : stage
    File.write("/tmp/call-center-acw-form-schema-#{suffix}.json", JSON.pretty_generate(report(stage)))
  end

  def self.owned?
    config = ActiveRecord::Base.connection_db_config
    databases = %w[jrc_sd_bc_portal_concurrency_20261025_test jrc_cc_access_schema_reload_synthetic]
    Rails.env.test? && config.configuration_hash[:host] == '127.0.0.1' && databases.include?(config.database)
  end

  def self.report(stage)
    migration = CreateContactCenterAcwForms.new
    components = CreateContactCenterAcwForms::SchemaReceipt.new(ActiveRecord::Base.connection).components
    { stage: stage, structure: structure, stored: ActiveRecord::Base.connection.table_comment(:jrc_contact_center_acw_form_templates),
      calculated: migration.send(:schema_receipt), escape_html: ActiveSupport.escape_html_entities_in_json, components: components,
      component_hashes: components.transform_values { |value| Digest::SHA256.hexdigest(JSON.generate(value)) } }
  end

  def self.structure
    connection = ActiveRecord::Base.connection
    CreateContactCenterAcwForms::SchemaReceipt::TABLES.index_with do |table|
      { columns: connection.columns(table).map(&:name).sort, checks: connection.check_constraints(table).map(&:name).sort,
        foreign_keys: connection.foreign_keys(table).length }
    end
  end
end
