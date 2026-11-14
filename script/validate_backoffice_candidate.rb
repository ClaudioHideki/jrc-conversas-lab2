# Run only against the disposable CI database, before any test uploads exist.
raise 'Disposable test database required' unless Rails.env.test? &&
  ActiveRecord::Base.connection_db_config.database == 'backoffice_test'

require 'open3'

%w[pdftotext pdftoppm tesseract identify].each do |command|
  _, _, status = Open3.capture3('sh', '-c', 'command -v "$1"', 'candidate-check', command)
  raise "Missing documentary dependency: #{command}" unless status.success?
end
languages, _, status = Open3.capture3('tesseract', '--list-langs')
raise 'OCR languages missing' unless status.success? && %w[por eng].all? { |lang| languages.lines.map(&:strip).include?(lang) }

account = Account.create!(name: 'Disposable candidate migration fixture')
account.enable_features!('jrc_crm')
actor = User.create!(name: 'Synthetic migration actor', email: "migration-#{SecureRandom.uuid}@example.test",
  password: "Aa1!#{SecureRandom.hex(24)}", confirmed_at: Time.current)
AccountUser.create!(account: account, user: actor, role: :administrator)
order = account.jrc_crm_sales_orders.create!(owner: actor, status: 'approved', source_type: 'manual', order_origin: 'direct_sale')
record = account.jrc_crm_backoffice_requests.create!(sales_order: order, owner: actor, requested_by: actor,
  title: 'Preserve legacy workflow and data', stage: 'finance', metadata: { 'migration_fixture' => true })
# Reproduce an existing pre-v2 row; current model creation selects workflow v2.
record.update_column(:workflow_version, 1)
expected = record.reload.attributes.except('workflow_version')
raise 'Schema unexpectedly has documentary data' unless JrcBackoffice::DocumentVersion.count.zero?

context = ActiveRecord::MigrationContext.new(Rails.root.join('db/migrate'))
before_versions = context.get_all_versions.sort
raise 'Supported Backoffice schema required' unless ([20261101190000, 20261101200000] - before_versions).empty?

# The supported main already contains these migrations. Reverting only them
# would remove tables referenced by later scans and signature artifacts.
# The populated main-to-candidate upgrade is proved by jrc_ag_ci_fixture.rb;
# this fixture proves forward convergence without changing existing data.
2.times { context.migrate }
raise 'Pending migrations remain' if context.needs_migration?
raise 'Applied migration history was removed' unless (before_versions - context.get_all_versions).empty?

connection = ActiveRecord::Base.connection
JrcCrm::BackofficeRequest.reset_column_information
preserved = JrcCrm::BackofficeRequest.find(record.id)
raise 'Existing data changed on upgrade' unless preserved.attributes.except('workflow_version') == expected
raise 'Existing record did not keep legacy workflow' unless preserved.workflow_version == 1
raise 'Legacy stage order changed' unless preserved.workflow_stages == JrcCrm::BackofficeRequest::STAGES
raise 'New versions table missing' unless connection.table_exists?(:jrc_backoffice_document_versions)
raise 'New analyses table missing' unless connection.table_exists?(:jrc_backoffice_document_analyses)
raise 'New decisions table missing' unless connection.table_exists?(:jrc_backoffice_document_decisions)
puts 'Supported schema, idempotent forward migrations, legacy data and OCR dependencies verified in backoffice_test.'
