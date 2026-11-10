require 'rails_helper'
require 'rubygems/package'
require 'zlib'

RSpec.describe 'Native Backoffice documentary package', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:order) { account.jrc_crm_sales_orders.create!(owner: actor, status: 'approved') }
  let(:operation) do
    account.jrc_crm_backoffice_requests.create!(sales_order: order, owner: actor, requested_by: actor,
                                                request_kind: 'fulfillment', stage: 'finance', title: 'Synthetic final operation',
                                                metadata: { finance_required: false, document_checklist: [
                                                  { key: 'proof', source: 'manual', required: false, blocking: false }
                                                ] })
  end
  let(:url) { "/api/v1/accounts/#{account.id}/crm/backoffice_requests/#{operation.id}/completion_package" }
  let(:service) { JrcBackoffice::CompletionPackage.new(account: account, actor: actor, request_id: operation.id) }
  let(:documents) { JrcBackoffice::Documents.new(request: operation, actor: actor) }
  let(:version) do
    documents.upload!(key: 'proof', file: fixture_file_upload('sample.pdf', 'application/pdf'), idempotency_key: SecureRandom.uuid)
  end

  before { account.enable_features!('jrc_crm') }

  it 'exports actual bytes of every safe immutable version and an exact manifest with no private snapshots' do
    first = version
    second = documents.upload!(key: 'proof', file: fixture_file_upload('sample.pdf', 'application/pdf'), idempotency_key: SecureRandom.uuid)
    [first, second].each do |row|
      # Simulated clean observations; this is not external scanner acceptance.
      JrcBackoffice::DocumentScan.create!(account: account, document_version: row, source_blob: row.file.blob, attempt: 1,
                                          state: 'clean', expected_sha256: row.sha256, observed_sha256: row.sha256,
                                          scanner_adapter: 'clamav-instream-v1')
    end
    second.decisions.create!(actor: actor, status: 'approved', reason: 'Synthetic private reviewer rationale')
    operation.advance!(actor: actor)
    get "#{url}/download", headers: headers
    expect(response).to have_http_status(:ok), response.body
    expect(response.headers).to include('cache-control' => 'no-store', 'x-content-type-options' => 'nosniff')
    entries = {}
    Zlib::GzipReader.wrap(StringIO.new(response.body)) do |gzip|
      Gem::Package::TarReader.new(gzip) { |tar| tar.each { |entry| entries[entry.full_name] = entry.read } }
    end
    expect(entries.except('manifest.json').transform_values { |bytes| Digest::SHA256.hexdigest(bytes) })
      .to eq("documents/#{first.id}/v1.pdf" => first.sha256, "documents/#{second.id}/v2.pdf" => second.sha256)
    manifest = JSON.parse(entries.fetch('manifest.json'))
    expect(manifest).to include('coverage' => 'available', 'request_id' => operation.id, 'responsible_id' => actor.id,
                                'completed_at' => operation.reload.completed_at.as_json)
    expect(manifest['files'].last).to include('id' => second.id, 'version' => 2, 'actor_id' => actor.id, 'review_status' => 'approved',
                                              'decisions' => [a_hash_including('actor_id' => actor.id, 'status' => 'approved')])
    expect(entries.fetch('manifest.json')).not_to include('source_snapshot', 'Synthetic private reviewer rationale', 'token', 'service_name')
    audit = JrcCrm::AuditEvent.find_by!(account: account, event_type: 'backoffice_completion_package_accessed')
    expect(audit.metadata['sha256']).to eq(Digest::SHA256.hexdigest(response.body))
  end

  it 'reports quarantine and missing required files honestly and never downloads unscanned bytes' do
    row = version
    operation.advance!(actor: actor)
    operation.update!(metadata: operation.metadata.merge('required_documents' => ['missing']))
    allow(row.file.blob.service).to receive(:download).and_raise('Unscanned bytes must not be read')
    get url, headers: headers
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body).to include('coverage' => 'incomplete')
    expect(response.parsed_body['files'].first).to include('id' => row.id, 'availability' => 'blocked', 'scan_state' => 'pending')
    expect(response.parsed_body['missing']).to include('kind' => 'document', 'key' => 'missing', 'reason' => 'REQUIRED_DOCUMENT_UNAVAILABLE')
    expect { service.download }.not_to raise_error
  end

  it 'preserves a legacy signed document without inventing a verified version-bound artifact' do
    contract = account.jrc_crm_contracts.create!(sales_order: order, owner: actor)
    operation.update!(contract: contract, workflow_version: 1)
    contract.signed_document.attach(io: File.open(Rails.root.join('spec/fixtures/files/sample.pdf')),
                                    filename: 'synthetic-signed.pdf', content_type: 'application/pdf')
    contract.update!(signature_status: 'signed', signed_at: Time.current, signed_by_name: 'Synthetic signer')
    operation.advance!(actor: actor)
    get url, headers: headers
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body['signature']).to eq('status' => 'signed', 'artifact_available' => false)
    expect(response.parsed_body['missing']).to include('kind' => 'signed_contract', 'reason' => 'VERSION_BOUND_SIGNED_ARTIFACT_UNAVAILABLE')
    expect(contract.reload.signed_document).to be_attached
  end

  it 'refuses unfinished operations on both preview and download' do
    [url, "#{url}/download"].each do |path|
      get path, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('REQUEST_NOT_COMPLETED')
    end
  end

  it 'enforces tenant and native owner scope even with forged query parameters' do
    operation.advance!(actor: actor)
    foreign = create(:user, account: create(:account), role: :administrator)
    other = create(:user, account: account, role: :agent)
    [url, "#{url}/download"].each do |path|
      get path, headers: foreign.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
      get path, headers: other.create_new_auth_token, params: { user_id: actor.id, account_id: account.id, owner_id: actor.id }
      expect(response).to have_http_status(:not_found)
    end
  end

  it 'checks native unit coverage again after a grant is revoked' do
    company = account.master_companies.create!(name: 'Synthetic issuer', relationship_type: 'internal')
    unit = account.jrc_crm_business_units.create!(name: 'Synthetic unit', code: 'package-unit', company_id: company.id)
    grant = JrcCrm::UserBusinessUnit.create!(account: account, user: actor, company: company, business_unit: unit,
                                             scope: 'BUSINESS_UNIT', structure_managed: true)
    order.update!(business_unit: unit)
    operation.update!(business_unit: unit)
    operation.advance!(actor: actor)
    get url, headers: headers
    expect(response).to have_http_status(:ok), response.body
    grant.update!(active: false)
    get "#{url}/download", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'fails closed if membership is revoked while reading private bytes and records no successful package audit' do
    row = version
    JrcBackoffice::DocumentScan.create!(account: account, document_version: row, source_blob: row.file.blob, attempt: 1,
                                        state: 'clean', expected_sha256: row.sha256, observed_sha256: row.sha256,
                                        scanner_adapter: 'clamav-instream-v1')
    operation.advance!(actor: actor)
    member = account.account_users.find_by!(user: actor)
    role = create(:custom_role, account: account, permissions: ['contact_manage'])
    allow(row.file.blob.service).to receive(:download).and_wrap_original do |original, *args|
      bytes = original.call(*args)
      member.update!(custom_role: role)
      bytes
    end
    expect { service.download }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'backoffice_completion_package_accessed')).to be_empty
  end

  it 'rejects oversized exports before reading files' do
    row = version
    JrcBackoffice::DocumentScan.create!(account: account, document_version: row, source_blob: row.file.blob, attempt: 1,
                                        state: 'clean', expected_sha256: row.sha256, observed_sha256: row.sha256,
                                        scanner_adapter: 'clamav-instream-v1')
    operation.advance!(actor: actor)
    stub_const('JrcBackoffice::CompletionPackage::MAX_BYTES', 1)
    expect(row.file.blob.service).not_to receive(:download)
    get "#{url}/download", headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('PACKAGE_TOO_LARGE')
  end

  it 'does not export bytes that no longer match a clean observation' do
    row = version
    JrcBackoffice::DocumentScan.create!(account: account, document_version: row, source_blob: row.file.blob, attempt: 1,
                                        state: 'clean', expected_sha256: row.sha256, observed_sha256: row.sha256,
                                        scanner_adapter: 'clamav-instream-v1')
    operation.advance!(actor: actor)
    allow(row.file.blob.service).to receive(:download).and_return('tampered synthetic bytes')
    expect { service.download }.to raise_error(ActiveStorage::IntegrityError)
    get "#{url}/download", headers: headers
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['code']).to eq('PACKAGE_FILE_INTEGRITY')
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'backoffice_completion_package_accessed')).to be_empty
  end

  it 'reports unavailable stored bytes without returning an empty replacement file or a success audit' do
    row = version
    JrcBackoffice::DocumentScan.create!(account: account, document_version: row, source_blob: row.file.blob, attempt: 1,
                                        state: 'clean', expected_sha256: row.sha256, observed_sha256: row.sha256,
                                        scanner_adapter: 'clamav-instream-v1')
    operation.advance!(actor: actor)
    allow(row.file.blob.service).to receive(:download).and_raise(ActiveStorage::FileNotFoundError)
    get "#{url}/download", headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('PACKAGE_FILE_UNAVAILABLE')
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'backoffice_completion_package_accessed')).to be_empty
  end

  it 'includes the real generated contractual PDF through the native version download and retains its exact identity' do
    contract = account.jrc_crm_contracts.create!(sales_order: order, owner: actor, content_override: 'Synthetic contract terms')
    operation.update!(contract: contract, workflow_version: 1)
    reader = JrcBackoffice::ContractVersions.new(account: account, actor: actor, request_id: operation.id)
    pdf = reader.create!(idempotency_key: SecureRandom.uuid, expected_source_digest: reader.source_digest(contract.id),
                         change_reason: 'Synthetic first version')
    contract.signed_document.attach(io: File.open(Rails.root.join('spec/fixtures/files/sample.pdf')),
                                    filename: 'synthetic-legacy-signed.pdf', content_type: 'application/pdf')
    contract.update!(signature_status: 'signed', signed_at: Time.current, signed_by_name: 'Synthetic legacy signer')
    operation.reload.advance!(actor: actor)
    entries = {}
    Zlib::GzipReader.wrap(StringIO.new(service.download)) do |gzip|
      Gem::Package::TarReader.new(gzip) { |tar| tar.each { |entry| entries[entry.full_name] = entry.read } }
    end
    expect(Digest::SHA256.hexdigest(entries.fetch("contracts/#{contract.id}/v1.pdf"))).to eq(pdf.pdf_sha256)
    expect(JSON.parse(entries.fetch('manifest.json'))['files']).to include(a_hash_including('id' => pdf.id, 'version' => 1,
                                                                                            'kind' => 'contract_version'))
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'backoffice_contract_version_accessed', resource_id: pdf.id)).to exist
  end

  it 'aborts if completion is invalidated during private storage I/O' do
    row = version
    JrcBackoffice::DocumentScan.create!(account: account, document_version: row, source_blob: row.file.blob, attempt: 1,
                                        state: 'clean', expected_sha256: row.sha256, observed_sha256: row.sha256,
                                        scanner_adapter: 'clamav-instream-v1')
    operation.advance!(actor: actor)
    allow(row.file.blob.service).to receive(:download).and_wrap_original do |original, *args|
      bytes = original.call(*args)
      operation.update!(status: 'in_progress', stage: 'finance', completed_at: nil)
      bytes
    end
    expect { service.download }.to raise_error(JrcBackoffice::CompletionReport::NotCompleted)
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'backoffice_completion_package_accessed')).to be_empty
  end
end
