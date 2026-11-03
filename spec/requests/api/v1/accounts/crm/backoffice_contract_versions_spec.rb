require 'rails_helper'

RSpec.describe 'Backoffice immutable contract version API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account) }
  let(:order) { account.jrc_crm_sales_orders.create!(owner: admin, contact: contact, status: 'approved') }
  let(:contract) do
    account.jrc_crm_contracts.create!(sales_order: order, owner: admin, contact: contact, content_override: 'TESTE SINTÉTICO — Minuta da API.')
  end
  let(:operation) do
    account.jrc_crm_backoffice_requests.create!(sales_order: order, contract: contract, owner: admin, requested_by: admin,
                                                contact: contact, title: 'TESTE SINTÉTICO — API de versões', stage: 'contract',
                                                metadata: { contract_required: true })
  end
  let(:url) { "/api/v1/accounts/#{account.id}/crm/backoffice_requests/#{operation.id}/contract_versions" }
  let(:headers) { admin.create_new_auth_token }
  let(:version) do
    JrcBackoffice::ContractVersions.new(account: account, actor: admin, request_id: operation.id).create!(
      idempotency_key: SecureRandom.uuid, expected_source_digest: JrcBackoffice::ContractSnapshot.digest(contract.reload),
      change_reason: 'Primeira minuta'
    )
  end

  before { account.enable_features!('jrc_crm') }

  it 'generates and reloads the exact revision through the scoped API' do
    get url, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('signer_directory_access')).to be(true)
    digest = response.parsed_body.dig('contract', 'source_digest')
    post url, headers: headers, params: { idempotency_key: SecureRandom.uuid, expected_source_digest: digest,
                                          change_reason: 'Revisão de teste', account_id: 999, created_by_id: 999 }, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch('id')
    expect(response.parsed_body).not_to have_key('source_snapshot')
    expect(JrcBackoffice::ContractVersion.find(id)).to have_attributes(account_id: account.id, created_by_id: admin.id)
    get url, headers: headers
    expect(response.parsed_body.fetch('data').first).to include('id' => id, 'number' => 1, 'current' => true)
  end

  it 'streams the exact stored PDF without permitting a browser cache' do
    record = version
    get "#{url}/#{record.id}/pdf", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(Digest::SHA256.hexdigest(response.body)).to eq(record.pdf_sha256)
  end

  it 'rejects other accounts and unassigned users on index, differences and downloads' do
    record = version
    agent = create(:user, account: account, role: :agent)
    [url, "#{url}/#{record.id}/pdf", "#{url}/#{record.id}/differences"].each do |path|
      get path, headers: agent.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end
    foreign = create(:account)
    foreign_actor = create(:user, account: foreign, role: :administrator)
    get "#{url}/#{record.id}/pdf", headers: foreign_actor.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects a stale preview without showing a successful generation' do
    get url, headers: headers
    digest = response.parsed_body.dig('contract', 'source_digest')
    preserved_ids = JrcBackoffice::ContractVersion.order(:id).pluck(:id)
    contract.update!(content_override: 'TESTE SINTÉTICO — Mudou antes de salvar.')
    post url, headers: headers, params: { idempotency_key: SecureRandom.uuid, expected_source_digest: digest, change_reason: 'Prévia antiga' },
              as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['code']).to eq('CONTRACT_SOURCE_CHANGED')
    expect(JrcBackoffice::ContractVersion.order(:id).pluck(:id)).to eq(preserved_ids)
  end

  it 'bounds the history on the server and does not expose encrypted source columns' do
    first = version
    10.times do |index|
      JrcBackoffice::ContractVersion.create!(first.attributes.except('id', 'created_at', 'updated_at').merge(
                                               'number' => index + 2, 'idempotency_key' => SecureRandom.uuid,
                                               'change_reason' => 'TESTE SINTÉTICO — Histórico paginado'
                                             ))
    end
    get url, headers: headers, params: { page: 1, per_page: 10_000 }
    expect(response.parsed_body.fetch('data').length).to eq(10)
    expect(response.parsed_body.fetch('meta')).to include('total' => 11, 'per_page' => 10)
    get url, headers: headers, params: { page: 2 }
    expect(response.parsed_body.fetch('data').pluck('number')).to eq([1])
    expect(response.body).not_to include('source_snapshot', 'pdf_blob_id', 'Minuta da API')
  end

  it 'blocks generic bearer and disk routes and prevents attaching the protected PDF to another record' do
    blob = version.pdf_blob
    get rails_storage_redirect_path(blob)
    expect(response).to have_http_status(:not_found)
    get rails_storage_proxy_path(blob)
    expect(response).to have_http_status(:not_found)
    variation = ActiveStorage::Variation.wrap(resize_to_limit: [100, 100]).key
    get rails_blob_representation_proxy_path(variation_key: variation, signed_blob_id: blob.signed_id, filename: blob.filename)
    expect(response).to have_http_status(:not_found)
    key = ActiveStorage.verifier.generate({ key: blob.key, disposition: 'attachment', content_type: blob.content_type,
                                            service_name: blob.service_name }, purpose: :blob_key)
    get rails_disk_service_path(encoded_key: key, filename: blob.filename)
    expect(response).to have_http_status(:not_found)
    upload_key = ActiveStorage.verifier.generate({ key: blob.key, content_type: blob.content_type, content_length: blob.byte_size,
                                                   checksum: blob.checksum, service_name: blob.service_name }, purpose: :blob_token)
    put update_rails_disk_service_path(encoded_token: upload_key), params: 'replacement'
    expect(response).to have_http_status(:not_found)
    expect { ActiveStorage::Attachment.create!(record: admin, name: 'avatar', blob: blob) }.to raise_error(ActiveRecord::RecordInvalid)
    ordinary = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('Ordinary native file'), filename: 'ordinary.txt', content_type: 'text/plain')
    get rails_storage_redirect_path(ordinary)
    expect(response).to have_http_status(:found)
  end

  it 'lets the assigned analyst edit the draft while retaining native financial locks and earlier PDFs' do
    first = version
    original_pdf = first.pdf_blob.download
    agent = create(:user, account: account, role: :agent)
    operation.update!(owner: agent)
    edit_url = "/api/v1/accounts/#{account.id}/crm/backoffice_requests/#{operation.id}/contract"
    get edit_url, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:ok)
    digest = response.parsed_body.fetch('source_digest')
    patch edit_url, headers: agent.create_new_auth_token,
                    params: { expected_source_digest: digest,
                              contract: { content_override: 'TESTE SINTÉTICO — Minuta revisada pelo analista' } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(contract.reload.content_override).to include('revisada pelo analista')
    expect(first.reload.pdf_blob.download).to eq(original_pdf)
    preserved = contract.attributes.slice('monthly_cents', 'one_time_cents', 'payment_condition', 'lifecycle_metadata')
    get edit_url, headers: agent.create_new_auth_token
    patch edit_url, headers: agent.create_new_auth_token,
                    params: { expected_source_digest: response.parsed_body.fetch('source_digest'),
                              contract: { monthly_cents: 1, one_time_cents: 1 } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(contract.reload.attributes.slice(*preserved.keys)).to eq(preserved)
  end

  it 'does not grant draft editing to unassigned actors or allow it after a recorded signature' do
    agent = create(:user, account: account, role: :agent)
    edit_url = "/api/v1/accounts/#{account.id}/crm/backoffice_requests/#{operation.id}/contract"
    patch edit_url, headers: agent.create_new_auth_token, params: { contract: { notes: 'Outra carteira' } }, as: :json
    expect(response).to have_http_status(:not_found)
    contract.signed_document.attach(io: File.open(Rails.root.join('spec/fixtures/files/sample.pdf')), filename: 'synthetic.pdf',
                                    content_type: 'application/pdf')
    contract.update!(signature_status: 'signed', signed_at: Time.current, signed_by_name: 'TESTE SINTÉTICO')
    patch edit_url, headers: headers, params: { contract: { content_override: 'Não substituir a versão assinada' } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(contract.reload.content_override).to eq('TESTE SINTÉTICO — Minuta da API.')
  end

  it 'rejects a lost-update attempt after another authorized editor changes the draft' do
    edit_url = "/api/v1/accounts/#{account.id}/crm/backoffice_requests/#{operation.id}/contract"
    get edit_url, headers: headers
    digest = response.parsed_body.fetch('source_digest')
    contract.update!(content_override: 'TESTE SINTÉTICO — Edição concorrente preservada')
    patch edit_url, headers: headers, params: { expected_source_digest: digest, contract: { content_override: 'Prévia antiga' } }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['code']).to eq('CONTRACT_SOURCE_CHANGED')
    expect(contract.reload.content_override).to include('Edição concorrente preservada')
  end

  it 'does not let an administrator cross the operator and unit boundary after coverage is restricted' do
    operator_a = account.master_companies.create!(name: 'TESTE SINTÉTICO — Operadora A', relationship_type: 'internal')
    operator_b = account.master_companies.create!(name: 'TESTE SINTÉTICO — Operadora B', relationship_type: 'internal')
    unit_a = account.jrc_crm_business_units.create!(name: 'TESTE-A', code: 'TESTE-A', operating_company: operator_a)
    unit_b = account.jrc_crm_business_units.create!(name: 'TESTE-B', code: 'TESTE-B', operating_company: operator_b)
    grant = account.jrc_crm_user_business_units.create!(user: admin, scope: 'GROUP', structure_managed: true, active: true)
    order.update!(business_unit: unit_b)
    contract.update!(business_unit: unit_b)
    operation.update!(business_unit: unit_b)
    record = version
    grant.destroy!
    account.jrc_crm_user_business_units.create!(user: admin, scope: 'BUSINESS_UNIT', company: operator_a,
                                                business_unit: unit_a, structure_managed: true, active: true)
    [url, "#{url}/#{record.id}/pdf", "#{url}/#{record.id}/differences"].each do |path|
      get path, headers: headers
      expect(response).to have_http_status(:not_found)
    end
    edit_url = "/api/v1/accounts/#{account.id}/crm/backoffice_requests/#{operation.id}/contract"
    patch edit_url, headers: headers,
                    params: { expected_source_digest: record.source_digest, contract: { notes: 'Tentativa de outra operadora' } }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(contract.reload.notes).not_to eq('Tentativa de outra operadora')
  end
end
