# Executed inside the exact candidate image on a private, disposable Docker network.
raise 'Candidate-only smoke database required' unless Rails.env.production? &&
  ActiveRecord::Base.connection_db_config.database == 'backoffice_candidate_smoke_test'
raise 'Candidate revision mismatch' unless File.read('/app/.git_sha').strip == ENV.fetch('CANDIDATE_SHA')

require 'sidekiq/api'
require 'tempfile'

raise 'Sidekiq did not register with the isolated Redis' unless Sidekiq::ProcessSet.new.any? { |process| process['queues'].include?('low') }
account = Account.create!(name: 'Isolated candidate smoke')
account.enable_features!('jrc_crm')
actor = User.create!(name: 'Synthetic candidate actor', email: "candidate-#{SecureRandom.uuid}@example.test",
  password: "Aa1!#{SecureRandom.hex(24)}", confirmed_at: Time.current)
AccountUser.create!(account: account, user: actor, role: :administrator)
contact = account.contacts.create!(name: 'Synthetic candidate contact')
order = account.jrc_crm_sales_orders.create!(owner: actor, contact: contact, status: 'approved', source_type: 'manual', order_origin: 'direct_sale')
record = account.jrc_crm_backoffice_requests.create!(sales_order: order, owner: actor, requested_by: actor,
  contact: contact, title: 'Candidate image document processing', metadata: { 'required_documents' => ['identity'] })
raise 'New workflow not selected' unless record.workflow_version == 2
version = File.open('/candidate-fixture.png', 'rb') do |file|
  upload = ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: 'synthetic.png', type: 'image/png')
  JrcBackoffice::Documents.new(request: record, actor: actor).upload!(key: 'identity', file: upload,
    idempotency_key: 'candidate-smoke-document-upload')
end
deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 45
loop do
  break if version.reload.analysis
  raise 'Sidekiq did not finish the real documentary job' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

  sleep 0.5
end
analysis = version.analysis
raise 'OCR was not executed in Sidekiq' unless analysis.evidence['engine'] == 'tesseract'
raise 'OCR confidence not measured' unless analysis.evidence['ocr_confidence'].to_f > 60
raise 'Document was automatically released' unless analysis.state == 'review_required' && version.status == 'review_required'
raise 'Sensitive text entered the evidence payload' if analysis.evidence.key?('text')
puts 'Exact candidate: Rails boot, native schema, shared storage, Sidekiq heartbeat and real queued OCR verified.'
