require 'rails_helper'
require 'csv'

RSpec.describe 'Scoped Backoffice completion report', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:order) { account.jrc_crm_sales_orders.create!(owner: actor, status: 'approved') }
  let(:operation) do
    account.jrc_crm_backoffice_requests.create!(sales_order: order, owner: actor, requested_by: actor,
                                                request_kind: 'fulfillment', stage: 'finance', title: '=Synthetic formula',
                                                metadata: { finance_required: false })
  end
  let(:url) { "/api/v1/accounts/#{account.id}/crm/backoffice_requests/#{operation.id}/completion_report" }
  let(:service) { JrcBackoffice::CompletionReport.new(account: account, actor: actor, request_id: operation.id) }

  before { account.enable_features!('jrc_crm') }

  it 'exports a real completed request, exact operational dates and native SLA while preserving formula safety and private fields' do
    operation.advance!(actor: actor)
    operation.update!(description: 'SYNTHETIC PRIVATE NOTE', metadata: operation.metadata.merge('secret_token' => 'SYNTHETIC SECRET'))
    get url, headers: headers
    expect(response).to have_http_status(:ok), response.body
    expect(response.headers).to include('cache-control' => 'no-store', 'x-content-type-options' => 'nosniff')
    expect(response.headers['content-disposition']).to include("backoffice-#{operation.id}-completion.csv")
    report = CSV.parse(response.body.delete_prefix("\uFEFF"))
    expect(report).to include(%w[request status completed], ['request', 'completed_at', operation.reload.completed_at.iso8601],
                              ['request', 'title', "'=Synthetic formula"], ['order', 'order_number', order.order_number], %w[sla state stopped])
    expect(response.body).not_to include('SYNTHETIC PRIVATE NOTE', 'SYNTHETIC SECRET', 'token_digest', 'pubsub_token')
    expect(JrcCrm::AuditEvent.where(account: account, resource_id: operation.id, event_type: 'backoffice_completion_report_accessed').count).to eq(1)
  end

  it 'includes an authorized legacy contract without changing its version or claiming provider evidence' do
    contract = account.jrc_crm_contracts.create!(sales_order: order, owner: actor)
    operation.update!(workflow_version: 1, contract: contract)
    contract.signed_document.attach(io: File.open(Rails.root.join('spec/fixtures/files/sample.pdf')),
                                    filename: 'synthetic-legacy.pdf', content_type: 'application/pdf')
    contract.update!(signature_status: 'signed', signed_at: Time.current, signed_by_name: 'Synthetic legacy signer')
    operation.advance!(actor: actor)
    before = contract.reload.attributes.deep_dup
    get url, headers: headers
    expect(response).to have_http_status(:ok), response.body
    report = CSV.parse(response.body.delete_prefix("\uFEFF"))
    expect(report).to include(['contract', 'contract_number', contract.contract_number], %w[contract signature_status signed])
    expect(response.body).not_to include('Synthetic legacy signer', 'completion_reported', 'source_snapshot', 'provider_credential')
    expect(contract.reload.attributes).to eq(before)
  end

  it 'rejects an incomplete, canceled or merely labeled-complete request without audit success' do
    get url, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('code' => 'REQUEST_NOT_COMPLETED')
    operation.update!(status: 'canceled')
    get url, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    operation.update!(status: 'completed', completed_at: nil)
    get url, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'backoffice_completion_report_accessed')).to be_empty
  end

  it 'exports only the latest immutable document metadata without reading private files or claiming a scan result' do
    requirement = { key: 'proof', source: 'manual', label: 'Synthetic optional proof', required: false, blocking: false }
    operation.update!(metadata: operation.metadata.merge('document_checklist' => [requirement]))
    documents = JrcBackoffice::Documents.new(request: operation, actor: actor)
    2.times do
      documents.upload!(key: 'proof', file: fixture_file_upload('sample.pdf', 'application/pdf'), idempotency_key: SecureRandom.uuid)
    end
    latest = operation.document_versions.order(version: :desc).first!
    operation.reload.advance!(actor: actor)
    storages = operation.document_versions.map { |version| version.file.blob.service }.uniq
    storages.each { |storage| allow(storage).to receive(:download).and_raise('Report must not read private bytes') }
    get url, headers: headers
    expect(response).to have_http_status(:ok), response.body
    report = CSV.parse(response.body.delete_prefix("\uFEFF"))
    expect(report).to include(['document:proof', 'version_id', latest.id.to_s], ['document:proof', 'version', '2'],
                              ['document:proof', 'sha256', latest.sha256], ['document:proof', 'scan_state', 'pending'])
    expect(report.count { |row| row.first == 'document:proof' && row[1] == 'version' }).to eq(1)
    expect(operation.document_versions.count).to eq(2)
  end

  it 'rejects another tenant and another native operational owner' do
    operation.advance!(actor: actor)
    foreign = create(:user, account: create(:account), role: :administrator)
    get url, headers: foreign.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    other = create(:user, account: account, role: :agent)
    get url, headers: other.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'requires native issuer and unit coverage even for an administrator and hides the report after revocation' do
    company = account.master_companies.create!(name: 'Synthetic internal operator', relationship_type: 'internal')
    unit = account.jrc_crm_business_units.create!(name: 'Synthetic operational unit', code: 'completion-unit', company_id: company.id)
    grant = JrcCrm::UserBusinessUnit.create!(account: account, user: actor, company: company, business_unit: unit,
                                             scope: 'BUSINESS_UNIT', structure_managed: true)
    order.update!(business_unit: unit)
    operation.update!(business_unit: unit)
    operation.advance!(actor: actor)
    get url, headers: headers
    expect(response).to have_http_status(:ok), response.body
    grant.update!(active: false)
    get url, headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'reauthorizes membership after generation and does not record a successful export after revocation' do
    operation.advance!(actor: actor)
    membership = account.account_users.find_by!(user: actor)
    role = create(:custom_role, account: account, permissions: ['contact_manage'])
    allow(JrcServiceDesk::OperationalCsv).to receive(:generate).and_wrap_original do |original, *args|
      bytes = original.call(*args)
      membership.update!(custom_role: role)
      bytes
    end
    expect { service.call }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcCrm::AuditEvent.where(account: account, event_type: 'backoffice_completion_report_accessed')).to be_empty
  end
end
