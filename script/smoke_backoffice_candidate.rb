# Executed inside the exact candidate image on a private, disposable Docker network.
raise 'Candidate-only smoke database required' unless Rails.env.production? &&
  ActiveRecord::Base.connection_db_config.database == 'backoffice_candidate_smoke_test'
raise 'Candidate revision mismatch' unless File.read('/app/.git_sha').strip == ENV.fetch('CANDIDATE_SHA')

require 'sidekiq/api'
require 'tempfile'
require 'open3'

%w[pdftotext pdftoppm tesseract identify].each do |command|
  _, _, status = Open3.capture3('sh', '-c', 'command -v "$1"', 'candidate-check', command)
  raise "Candidate documentary dependency missing: #{command}" unless status.success?
end
languages, _, status = Open3.capture3('tesseract', '--list-langs')
raise 'Candidate OCR languages missing' unless status.success? && %w[por eng].all? { |lang| languages.lines.map(&:strip).include?(lang) }

sidekiq_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 45
until Sidekiq::ProcessSet.new.any? { |process| process['queues'].include?('low') }
  raise 'Sidekiq did not register with the isolated Redis' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > sidekiq_deadline

  sleep 0.5
end
account = Account.create!(name: 'Isolated candidate smoke')
account.enable_features!('jrc_crm')
actor = User.create!(name: 'Synthetic candidate actor', email: "candidate-#{SecureRandom.uuid}@example.test",
  password: "Aa1!#{SecureRandom.hex(24)}", confirmed_at: Time.current)
AccountUser.create!(account: account, user: actor, role: :administrator)
contact = account.contacts.create!(name: 'Synthetic candidate contact')
order = account.jrc_crm_sales_orders.create!(owner: actor, contact: contact, status: 'approved', source_type: 'manual', order_origin: 'direct_sale')
record = account.jrc_crm_backoffice_requests.create!(sales_order: order, owner: actor, requested_by: actor,
  contact: contact, title: 'Candidate image document processing', metadata: { 'required_documents' => %w[identity identity_pdf] })
raise 'New workflow not selected' unless record.workflow_version == 2
versions = Tempfile.create(['candidate-smoke-', '.pdf']) do |pdf|
  pdf.binmode
  pdf.write(JrcCrm::OrderPdfService.new(order).call)
  pdf.flush
  [['identity', '/candidate-fixture.png', 'image/png'], ['identity_pdf', pdf.path, 'application/pdf']].map do |key, path, type|
    File.open(path, 'rb') do |file|
      upload = ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: File.basename(path), type: type)
      JrcBackoffice::Documents.new(request: record, actor: actor).upload!(key: key, file: upload,
        idempotency_key: "candidate-smoke-document-upload-#{key}")
    end
  end
end

deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 45
loop do
  break if versions.all? { |version| version.reload.analysis }
  raise 'Sidekiq did not finish the real documentary job' if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

  sleep 0.5
end
image_analysis, pdf_analysis = versions.map(&:analysis)
raise 'OCR was not executed in Sidekiq' unless image_analysis.evidence['engine'] == 'tesseract'
raise 'OCR confidence not measured' unless image_analysis.evidence['ocr_confidence'].to_f > 60
raise 'PDF text was not extracted by Poppler' unless pdf_analysis.evidence['engine'] == 'poppler'
raise 'Digital text received invented OCR confidence' if pdf_analysis.evidence.key?('ocr_confidence')
versions.each do |version|
  analysis = version.analysis
  raise 'Document was automatically released' unless analysis.state == 'review_required' && version.status == 'review_required'
  raise 'Sensitive text entered the evidence payload' if analysis.evidence.key?('text')
end
puts "Candidate documentary evidence: tesseract confidence=#{image_analysis.evidence['ocr_confidence']}, " \
     'poppler PDF, queue=low, human review required.'
puts 'Exact candidate: Rails boot, native schema, shared storage, Sidekiq heartbeat and real queued OCR/PDF verified.'
