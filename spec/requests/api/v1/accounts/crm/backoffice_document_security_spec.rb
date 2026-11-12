require 'rails_helper'

RSpec.describe 'Backoffice protected document security API', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }
  let(:order) { account.jrc_crm_sales_orders.create!(owner: actor, contact: contact, status: 'approved') }
  let(:operation) do
    account.jrc_crm_backoffice_requests.create!(sales_order: order, owner: actor, requested_by: actor, contact: contact,
                                                title: 'TESTE SINTÉTICO — API documental', metadata: { required_documents: ['powers'] })
  end
  let(:file) { fixture_file_upload(Rails.root.join('spec/fixtures/files/sample.pdf'), 'application/pdf') }
  let(:version) do
    JrcBackoffice::Documents.new(request: operation, actor: actor).upload!(key: 'powers', file: file, idempotency_key: SecureRandom.uuid)
  end
  let(:base) { "/api/v1/accounts/#{account.id}/crm/backoffice_requests/#{operation.id}/document_versions" }
  let(:headers) { actor.create_new_auth_token }

  before { account.enable_features!('jrc_crm') }

  it 'keeps the applied manual requirement and uploaded version visible after native reconciliation' do
    requirement = { 'key' => 'powers', 'label' => 'Synthetic representation document', 'source' => 'manual',
                    'required' => true, 'blocking' => true }
    operation.update!(metadata: { document_checklist: [requirement] })
    post base, headers: headers, params: { document_key: 'powers', file: file, idempotency_key: SecureRandom.uuid }
    expect(response).to have_http_status(:created)
    uploaded_id = response.parsed_body.fetch('id')
    get base, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('requirements').map { |row| row.slice(*requirement.keys) }).to eq([requirement])
    expect(response.parsed_body.fetch('data').map { |row| row.fetch('id') }).to eq([uploaded_id])
    expect(operation.reload.metadata.fetch('document_checklist').first.fetch('status')).to eq('processing')
    expect(JrcBackoffice::DocumentVersion.find(uploaded_id).decisions).to be_empty
  end

  it 'shows quarantine and refuses download or approval without a persisted observation' do
    version.file.blob.update!(metadata: { service_desk_scan_state: 'clean' })
    get base, headers: headers
    expect(response.parsed_body.fetch('data').first.dig('safety', 'state')).to eq('pending')
    get "#{base}/#{version.id}", headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('code')).to eq('DOCUMENT_QUARANTINED')
    post "#{base}/#{version.id}/decision", headers: headers, params: { status: 'approved', reason: 'Cliente declarou limpo' }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(version.decisions).to be_empty
    expect(response.headers['Cache-Control']).to eq('no-store')
  end

  it 'downloads verified bytes through the scoped route and keeps the generic locator private' do
    # Scanner response is simulated here; the socket protocol is covered by DocumentSafety specs.
    scanner = instance_double(JrcServiceDesk::AttachmentScanner)
    allow(JrcServiceDesk::AttachmentScanner).to receive(:new).and_return(scanner)
    allow(scanner).to receive(:scan).with(version.file.blob, socket_path: anything).and_return(
      'service_desk_scan_state' => 'clean', 'service_desk_scan_sha256' => version.sha256
    )
    JrcBackoffice::DocumentSafety.new(version).scan!
    get "#{base}/#{version.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(Digest::SHA256.hexdigest(response.body)).to eq(version.sha256)
    get Rails.application.routes.url_helpers.rails_blob_path(version.file.blob, only_path: true)
    expect(response).to have_http_status(:not_found)
  end

  it 'queues verification without declaring the file clean or approved' do
    version
    expect do
      post "#{base}/#{version.id}/recheck", headers: headers
    end.to have_enqueued_job(JrcBackoffice::DocumentPreanalysisJob).with(version.id)
    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body).to eq('id' => version.id, 'status' => 'queued')
    expect(JrcBackoffice::DocumentScan.where(document_version: version)).to be_empty
    expect(version.decisions).to be_empty
  end

  it 'refuses the same reads and jobs for an unassigned actor or another account' do
    version
    unassigned = create(:user, account: account, role: :agent)
    token = unassigned.create_new_auth_token
    get "#{base}/#{version.id}", headers: token
    expect(response).to have_http_status(:not_found)
    post "#{base}/#{version.id}/recheck", headers: token
    expect(response).to have_http_status(:not_found)
    foreign = create(:user, account: create(:account), role: :administrator)
    get "#{base}/#{version.id}", headers: foreign.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'does not announce a queued check when the native enqueue is aborted' do
    version
    allow(JrcBackoffice::DocumentPreanalysisJob).to receive(:perform_later).with(version.id).and_return(false)
    post "#{base}/#{version.id}/recheck", headers: headers
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body).to eq('code' => 'DOCUMENT_CHECK_NOT_QUEUED')
    expect(JrcBackoffice::DocumentScan.where(document_version: version)).to be_empty
  end

  it 'uses server pagination and returns no bearer or storage identifiers' do
    6.times do
      JrcBackoffice::Documents.new(request: operation, actor: actor).upload!(key: 'powers', file: file, idempotency_key: SecureRandom.uuid)
    end
    get base, headers: headers
    expect(response.parsed_body.fetch('data').length).to eq(5)
    expect(response.parsed_body.fetch('meta')).to eq('page' => 1, 'pages' => 2, 'total' => 6, 'per_page' => 5)
    expect(response.body).not_to include('signed_id', 'blob_id', 'service_name')
    get base, headers: headers, params: { page: 2 }
    expect(response.parsed_body.fetch('data').length).to eq(1)
  end

  it 'does not return bytes after membership is revoked during storage I/O' do
    scanner = instance_double(JrcServiceDesk::AttachmentScanner)
    allow(JrcServiceDesk::AttachmentScanner).to receive(:new).and_return(scanner)
    allow(scanner).to receive(:scan).with(version.file.blob, socket_path: anything).and_return(
      'service_desk_scan_state' => 'clean', 'service_desk_scan_sha256' => version.sha256
    )
    JrcBackoffice::DocumentSafety.new(version).scan!
    token = headers
    blob = version.file.blob
    allow(blob.service).to receive(:download).with(blob.key).and_wrap_original do |method, *arguments|
      bytes = method.call(*arguments)
      AccountUser.find_by!(account: account, user: actor).destroy!
      bytes
    end
    get "#{base}/#{version.id}", headers: token
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to start_with('%PDF-')
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'backoffice_document_accessed')).to be_empty
  end

  it 'replays the same upload intent without creating another version' do
    key = SecureRandom.uuid
    post base, headers: headers, params: { document_key: 'powers', file: file, idempotency_key: key }
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch('id')
    post base, headers: headers, params: { document_key: 'powers', file: file, idempotency_key: key }
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.fetch('id')).to eq(id)
    expect(operation.document_versions.count).to eq(1)
  end
end
