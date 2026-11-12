require 'rails_helper'

# Native persistence and HTTP suite. Synthetic scanner evidence is NOT external
# antivirus acceptance; the existing scanner/socket suites retain that boundary.
RSpec.describe 'Backoffice document validity and review revisions', type: :request do
  include ActiveSupport::Testing::TimeHelpers
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }
  let(:order) { account.jrc_crm_sales_orders.create!(owner: actor, contact: contact, status: 'approved') }
  let(:operation) do
    account.jrc_crm_backoffice_requests.create!(sales_order: order, owner: actor, requested_by: actor, contact: contact,
      title: 'SYNTHETIC validity', workflow_version: 2, metadata: { required_documents: ['powers'] })
  end
  let(:upload) { fixture_file_upload(Rails.root.join('spec/fixtures/files/sample.pdf'), 'application/pdf') }
  let(:version) do
    JrcBackoffice::Documents.new(request: operation, actor: actor).upload!(key: 'powers', file: upload, idempotency_key: SecureRandom.uuid)
  end
  let(:url) { "/api/v1/accounts/#{account.id}/crm/backoffice_requests/#{operation.id}/document_versions/#{version.id}/decision" }
  let(:headers) { actor.create_new_auth_token }

  before do
    account.enable_features!('jrc_crm')
    scanner = instance_double(JrcServiceDesk::AttachmentScanner)
    allow(JrcServiceDesk::AttachmentScanner).to receive(:new).and_return(scanner)
    allow(scanner).to receive(:scan).and_return('service_desk_scan_state' => 'clean', 'service_desk_scan_sha256' => version.sha256)
    JrcBackoffice::DocumentSafety.new(version).scan!
    version.create_analysis!(state: 'review_required', analyzer_version: 'synthetic/1', evidence: { synthetic: true })
  end

  it 'stores immutable calendar validity and returns its revision' do
    travel_to(Time.utc(2026, 11, 9, 15)) do
      post url, headers: headers, as: :json, params: { status: 'approved', reason: 'Synthetic verified validity', expires_on: '2026-11-10', expected_decision_id: nil }
      expect(response).to have_http_status(:ok), response.body
      receipt = version.current_decision
      expect(receipt.expires_on).to eq(Date.new(2026, 11, 10))
      expect(receipt.validity_timezone).to eq('America/Sao_Paulo')
      expect(response.parsed_body['decision_revision']).to eq(receipt.id)
    end
  end

  it 'becomes expired after the captured local date without rewriting the old decision' do
    receipt = version.decisions.create!(actor: actor, status: 'approved', reason: 'Synthetic', expires_on: Date.new(2026, 11, 9), validity_timezone: 'America/Sao_Paulo')
    before = receipt.attributes.deep_dup
    travel_to(Time.utc(2026, 11, 10, 2, 59)) { expect(version.reload.status).to eq('approved') }
    travel_to(Time.utc(2026, 11, 10, 3, 0)) { expect(version.reload.status).to eq('expired') }
    expect(receipt.reload.attributes).to eq(before)
  end

  it 'rejects an approval with a date already expired and does not write a decision' do
    travel_to(Time.utc(2026, 11, 9, 15)) do
      expect do
        post url, headers: headers, as: :json, params: { status: 'approved', reason: 'Synthetic', expires_on: '2026-11-08', expected_decision_id: nil }
      end.not_to change(JrcBackoffice::DocumentDecision, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it 'rejects a stale decision revision without overwriting the newer review' do
    original = version.decisions.create!(actor: actor, status: 'rejected', reason: 'First')
    newest = version.decisions.create!(actor: actor, status: 'rejected', reason: 'Second')
    post url, headers: headers, as: :json, params: { status: 'approved', reason: 'Stale', expected_decision_id: original.id }
    expect(response).to have_http_status(:conflict)
    expect(version.current_decision.id).to eq(newest.id)
  end

  it 'preserves the existing date when a compatible legacy caller omits it' do
    version.decisions.create!(actor: actor, status: 'rejected', reason: 'Synthetic', expires_on: Date.new(2099, 1, 1), validity_timezone: 'UTC')
    post url, headers: headers, as: :json, params: { status: 'rejected', reason: 'Still rejected' }
    expect(response).to have_http_status(:ok)
    expect(version.current_decision.expires_on).to eq(Date.new(2099, 1, 1))
  end

  it 'keeps scanner quarantine blocking even when a validity date is supplied' do
    JrcBackoffice::DocumentScan.where(document_version: version).create!(account: account, document_version: version,
      source_blob: version.file.blob, attempt: 2, state: 'infected', expected_sha256: version.sha256,
      observed_sha256: version.sha256, scanner_adapter: 'clamav-instream-v1', failure_code: 'INFECTED')
    post url, headers: headers, as: :json, params: { status: 'approved', reason: 'Synthetic', expires_on: '2099-01-01' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(version.decisions).to be_empty
  end

  it 'denies foreign-account access without exposing validity or document content' do
    foreign = create(:user, account: create(:account), role: :administrator)
    post url, headers: foreign.create_new_auth_token, as: :json, params: { status: 'approved', reason: 'Denied', expires_on: '2099-01-01' }
    expect(response).to have_http_status(:unauthorized)
    expect(version.decisions).to be_empty
  end
  it 'blocks the current v2 stage when an approved document expires, despite cached metadata' do
    version.decisions.create!(actor: actor, status: 'approved', reason: 'Synthetic expiry',
      expires_on: Date.new(2026, 11, 9), validity_timezone: 'UTC')
    operation.update!(stage: 'documentation', metadata: operation.metadata.merge('document_statuses' => { 'powers' => 'approved' }))
    travel_to(Time.utc(2026, 11, 10, 12)) do
      expect(JrcBackoffice::DocumentGate.statuses(operation)['powers']).to eq('expired')
      expect(operation.stage_blockers.join(' ')).to include('powers')
    end
  end

  it 'rejects an explicit validity change without a review revision' do
    post url, headers: headers, as: :json, params: { status: 'approved', reason: 'No revision', expires_on: '2099-01-01' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(version.decisions).to be_empty
  end

  it 'rejects an orphan time zone even through an SQL insert bypassing model validation' do
    expect do
      ActiveRecord::Base.transaction(requires_new: true) do
        JrcBackoffice::DocumentDecision.insert_all!([{ document_version_id: version.id, actor_id: actor.id,
          status: 'approved', reason: 'Synthetic invalid pair', expires_on: nil, validity_timezone: 'UTC',
          created_at: Time.current, updated_at: Time.current }])
      end
    end.to raise_error(ActiveRecord::StatementInvalid)
  end

  it 'rejects a nonexistent calendar zone in the database guard' do
    expect do
      ActiveRecord::Base.transaction(requires_new: true) do
        JrcBackoffice::DocumentDecision.insert_all!([{ document_version_id: version.id, actor_id: actor.id,
          status: 'approved', reason: 'Synthetic invalid zone', expires_on: Date.new(2099, 1, 1), validity_timezone: 'Missing/JRCZone',
          created_at: Time.current, updated_at: Time.current }])
      end
    end.to raise_error(ActiveRecord::StatementInvalid)
  end

  it 'blocks direct contract preparation through the common release service after expiry' do
    version.decisions.create!(actor: actor, status: 'approved', reason: 'Synthetic expiry',
      expires_on: Date.new(2026, 11, 9), validity_timezone: 'UTC')
    travel_to(Time.utc(2026, 11, 10, 12)) do
      expect { JrcBackoffice::ContractRelease.check!(order: order, actor: actor) }
        .to raise_error(JrcBackoffice::Requirements::Blocked)
    end
  end

  it 'prevents rewriting a captured validity through a raw update' do
    row = version.decisions.create!(actor: actor, status: 'rejected', reason: 'Synthetic immutable decision',
      expires_on: Date.new(2099, 1, 1), validity_timezone: 'UTC')
    expect do
      ActiveRecord::Base.transaction(requires_new: true) do
        JrcBackoffice::DocumentDecision.where(id: row.id).update_all(expires_on: Date.new(2099, 2, 1))
      end
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(row.reload.expires_on).to eq(Date.new(2099, 1, 1))
  end

end
