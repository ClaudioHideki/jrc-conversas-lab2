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
expected = record.reload.attributes.except('workflow_version')
raise 'Schema unexpectedly has documentary data' unless JrcBackoffice::DocumentVersion.count.zero?

context = ActiveRecord::MigrationContext.new(Rails.root.join('db/migrate'))
context.run(:down, 20261101200000)
context.run(:down, 20261101190000)
connection = ActiveRecord::Base.connection
raise 'Workflow rollback failed' if connection.column_exists?(:jrc_crm_backoffice_requests, :workflow_version)
raise 'Document rollback failed' if connection.table_exists?(:jrc_backoffice_document_versions)
context.run(:up, 20261101190000)
context.run(:up, 20261101200000)
JrcCrm::BackofficeRequest.reset_column_information
preserved = JrcCrm::BackofficeRequest.find(record.id)
raise 'Existing data changed on upgrade' unless preserved.attributes.except('workflow_version') == expected
raise 'Existing record did not keep legacy workflow' unless preserved.workflow_version == 1
raise 'Legacy stage order changed' unless preserved.workflow_stages == JrcCrm::BackofficeRequest::STAGES
raise 'New versions table missing' unless connection.table_exists?(:jrc_backoffice_document_versions)
raise 'New analyses table missing' unless connection.table_exists?(:jrc_backoffice_document_analyses)
raise 'New decisions table missing' unless connection.table_exists?(:jrc_backoffice_document_decisions)
puts 'Candidate migration upgrade/rollback, legacy data and OCR dependencies verified in backoffice_test.'
