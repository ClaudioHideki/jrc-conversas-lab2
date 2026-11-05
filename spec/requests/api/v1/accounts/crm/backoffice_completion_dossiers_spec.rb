require 'rails_helper'
require 'rubygems/package'
require 'zlib'

RSpec.describe 'Sealed native Backoffice dossiers', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:order) { account.jrc_crm_sales_orders.create!(owner: actor, status: 'approved') }
  let(:operation) do
    account.jrc_crm_backoffice_requests.create!(
      sales_order: order, owner: actor, requested_by: actor, request_kind: 'fulfillment', stage: 'finance', title: 'Synthetic sealed dossier',
      metadata: { finance_required: false, document_checklist: [{ key: 'proof', source: 'manual', required: false, blocking: false }] }
    )
  end
  let(:documents) { JrcBackoffice::Documents.new(request: operation, actor: actor) }
  let(:version) { documents.upload!(key: 'proof', file: fixture_file_upload('sample.pdf', 'application/pdf'), idempotency_key: SecureRandom.uuid) }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/backoffice_requests/#{operation.id}/completion_dossiers" }

  before do
    config = ActiveRecord::Base.connection_db_config
    raise 'Use only the isolated dossier test database' unless Rails.env.test? && config.database == 'jrc_rel_v2_candidate_test'

    account.enable_features!('jrc_crm')
  end

  def clean(row)
    JrcBackoffice::DocumentScan.create!(account: account, document_version: row, source_blob: row.file.blob, attempt: 1,
                                        state: 'clean', expected_sha256: row.sha256, observed_sha256: row.sha256,
                                        scanner_adapter: 'clamav-instream-v1')
  end

  def seal_current
    get url, headers: headers
    expect(response).to have_http_status(:ok), response.body
    digest = response.parsed_body.fetch('candidate_digest')
    post url, headers: headers, params: { completion_dossier: { expected_manifest_digest: digest } }
    expect(response).to have_http_status(:created), response.body
    JrcBackoffice::CompletionDossier.find(response.parsed_body.fetch('id'))
  end

  # One native persisted lifecycle proves archive, idempotence, revisions and independent SQL protection.
  # rubocop:disable RSpec/MultipleExpectations
  it 'stores immutable exact archive bytes and new revisions without replacing an older seal or exposing its locator' do
    clean(version)
    operation.advance!(actor: actor)
    row = seal_current
    expect(row.integrity?).to be(true)
    same = seal_current
    expect(same.id).to eq(row.id)
    get "#{url}/#{row.id}/download", headers: headers
    expect(response).to have_http_status(:ok)
    original_bytes = response.body
    expect(Digest::SHA256.hexdigest(original_bytes)).to eq(row.archive_sha256)
    entries = {}
    Zlib::GzipReader.wrap(StringIO.new(original_bytes)) do |gzip|
      Gem::Package::TarReader.new(gzip) { |tar| tar.each { |file| entries[file.full_name] = file.read } }
    end
    expect(JSON.parse(entries.fetch('manifest.json'))).to eq(row.snapshot.fetch('manifest'))
    expect(Digest::SHA256.hexdigest(entries.fetch("documents/#{version.id}/v1.pdf"))).to eq(version.sha256)
    get Rails.application.routes.url_helpers.rails_blob_path(row.archive_blob, only_path: true)
    expect(response).to have_http_status(:not_found)
    expect { row.update!(archive_sha256: '0' * 64) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect do
      JrcBackoffice::CompletionDossier.transaction(requires_new: true) { JrcBackoffice::CompletionDossier.where(id: row.id).delete_all }
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect do
      ActiveStorage::Blob.transaction(requires_new: true) { row.archive_blob.update!(filename: 'tampered.tar.gz') }
    end.to raise_error(ActiveRecord::StatementInvalid)
    post url.sub('/completion_dossiers', '/reopen'), headers: headers, params: { stage: 'finance' }
    expect(response).to have_http_status(:ok)
    second = documents.upload!(key: 'proof', file: fixture_file_upload('sample.pdf', 'application/pdf'), idempotency_key: SecureRandom.uuid)
    clean(second)
    operation.reload.advance!(actor: actor)
    revision = seal_current
    expect(revision.number).to eq(2)
    expect(row.reload.archive_sha256).to eq(Digest::SHA256.hexdigest(original_bytes))
  end
  # rubocop:enable RSpec/MultipleExpectations

  it 'refuses stale candidates and files without security admission; a later quarantine blocks the preserved seal' do
    version
    operation.advance!(actor: actor)
    get url, headers: headers
    expect(response.parsed_body.fetch('can_seal')).to be(false)
    post url, headers: headers, params: { completion_dossier: { expected_manifest_digest: '0' * 64 } }
    expect(response).to have_http_status(:conflict)
    clean(version)
    row = seal_current
    JrcBackoffice::DocumentScan.create!(account: account, document_version: version, source_blob: version.file.blob, attempt: 2,
                                        state: 'infected', expected_sha256: version.sha256, observed_sha256: version.sha256,
                                        scanner_adapter: 'clamav-instream-v1')
    get "#{url}/#{row.id}/download", headers: headers
    expect(response).to have_http_status(:conflict)
    expect(row.reload.integrity?).to be(true)
  end

  it 'requires both historical unit coverage and current native access after a source relocation' do
    account.enable_features!('jrc_customer_master')
    issuer = account.master_companies.create!(name: 'Synthetic dossier issuer', relationship_type: 'internal', tax_id: '11444777000161')
    units = Array.new(2) do |index|
      account.jrc_crm_business_units.create!(name: "Synthetic #{index}", code: SecureRandom.hex(6), company_id: issuer.id)
    end
    grants = units.map do |unit|
      account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company_id: issuer.id,
                                                  business_unit: unit, structure_managed: true, active: true)
    end
    order.update!(business_unit: units.first)
    operation.update!(business_unit: units.first)
    clean(version)
    operation.advance!(actor: actor)
    row = seal_current
    order.update!(business_unit: units.last)
    operation.update!(business_unit: units.last)
    grants.first.update!(active: false)
    get "#{url}/#{row.id}/download", headers: headers
    expect(response).to have_http_status(:not_found)
    get url, headers: headers
    expect(response.parsed_body.fetch('data')).to be_empty
    expect(seal_current.number).to eq(2)
  end

  it 'rechecks membership after archive storage I/O and does not record a successful download' do
    clean(version)
    operation.advance!(actor: actor)
    row = seal_current
    allow(row.archive_blob.service).to receive(:open).and_wrap_original do |original, *args, **options, &block|
      original.call(*args, **options) do |file|
        account.disable_features!('jrc_crm')
        block.call(file)
      end
    end
    get "#{url}/#{row.id}/download", headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'backoffice_completion_dossier_accessed')).not_to exist
    account.enable_features!('jrc_crm')
    allow(row.archive_blob.service).to receive(:open).and_yield(StringIO.new('Synthetic corrupted archive'))
    get "#{url}/#{row.id}/download", headers: headers
    expect(response).to have_http_status(:conflict)
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'backoffice_completion_dossier_accessed')).not_to exist
  end

  it 'denies another account and a nonowner before returning archive metadata or bytes' do
    clean(version)
    operation.advance!(actor: actor)
    row = seal_current
    foreign = create(:user, account: create(:account), role: :administrator)
    get "#{url}/#{row.id}/download", headers: foreign.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    outsider = create(:user, account: account, role: :agent)
    get url, headers: outsider.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end
end
