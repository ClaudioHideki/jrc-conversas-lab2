require 'rails_helper'

RSpec.describe 'Backoffice contextual contract templates', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:issuer) { account.master_companies.create!(name: 'TESTE SINTÉTICO — Emitente de modelos', relationship_type: 'internal') }
  let(:unit) { account.jrc_crm_business_units.create!(name: 'TESTE SINTÉTICO — Unidade de modelos', code: 'TEMPLATES', company_id: issuer.id) }
  let(:contact) { create(:contact, account: account) }
  let(:order) { account.jrc_crm_sales_orders.create!(owner: actor, contact: contact, business_unit: unit, status: 'approved') }
  let(:contract) do
    account.jrc_crm_contracts.create!(sales_order: order, owner: actor, contact: contact, business_unit: unit,
                                      content_override: 'TESTE SINTÉTICO — Minuta antes da seleção.')
  end
  let(:operation) do
    account.jrc_crm_backoffice_requests.create!(sales_order: order, contract: contract, owner: actor, requested_by: actor,
                                                contact: contact, business_unit: unit, title: 'TESTE SINTÉTICO — Modelos', stage: 'contract')
  end
  let(:template) do
    account.jrc_crm_contract_templates.create!(name: 'ZZZ TESTE SINTÉTICO — Modelo elegível', category: 'Jurídico',
                                               body: 'TESTE SINTÉTICO — Texto do modelo {{ contrato.numero }}.',
                                               selection_rules: { operating_company_id: issuer.id })
  end
  let(:headers) { actor.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/backoffice_requests/#{operation.id}/contract" }

  before do
    account.enable_features!('jrc_crm')
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: issuer, business_unit: unit,
                                                structure_managed: true, active: true)
  end

  it 'paginates only matching active native templates without sending legal bodies or selection rules' do
    template
    11.times { |index| account.jrc_crm_contract_templates.create!(name: "AAA TESTE SINTÉTICO #{index}", body: 'Texto privado de teste') }
    account.jrc_crm_contract_templates.create!(name: 'TESTE SINTÉTICO — Inativo', body: 'Texto', active: false)
    account.jrc_crm_contract_templates.create!(name: 'TESTE SINTÉTICO — Prazo incompatível', body: 'Texto', selection_rules: { term_months: 36 })
    get "#{base}/templates", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.parsed_body['data'].length).to eq(10)
    expect(response.parsed_body['meta']).to include('total' => 12, 'pages' => 2)
    expect(response.body).not_to include('body', 'selection_rules', 'Texto privado')
    get "#{base}/templates", headers: headers, params: { page: 2 }
    expect(response.parsed_body['data'].pluck('id')).to include(template.id)
  end

  it 'searches names with literal wildcards instead of broadening the eligible registry' do
    template
    account.jrc_crm_contract_templates.create!(name: 'AAA TESTE SINTÉTICO — Alternativo', body: 'Texto privado de teste')
    get "#{base}/templates", headers: headers, params: { q: template.name }
    expect(response.parsed_body['data'].pluck('id')).to eq([template.id])
    get "#{base}/templates", headers: headers, params: { q: '%' }
    expect(response.parsed_body['data']).to eq([])
  end

  it 'uses native issuer rules and rejects a template that belongs to a different operating company' do
    other_issuer = account.master_companies.create!(name: 'TESTE SINTÉTICO — Outra emitente', relationship_type: 'internal')
    incompatible = account.jrc_crm_contract_templates.create!(name: 'TESTE SINTÉTICO — Outra emitente', body: 'Texto',
                                                              selection_rules: { operating_company_id: other_issuer.id })
    get "#{base}/templates", headers: headers
    expect(response.parsed_body['data'].pluck('id')).not_to include(incompatible.id)
    patch base, headers: headers, params: { expected_source_digest: JrcBackoffice::ContractSnapshot.digest(contract.reload),
                                            contract: { contract_template_id: incompatible.id, content_override: '' } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(contract.reload.contract_template_id).to be_nil
  end

  it 'selects the exact eligible template through native editing, records its reference and preserves the old PDF' do
    service = JrcBackoffice::ContractVersions.new(account: account, actor: actor, request_id: operation.id)
    first = service.create!(idempotency_key: SecureRandom.uuid, expected_source_digest: service.source_digest(contract.id),
                            change_reason: 'TESTE SINTÉTICO — Minuta original.')
    before = contract.financial_summary
    patch base, headers: headers, params: { expected_source_digest: JrcBackoffice::ContractSnapshot.digest(contract.reload),
                                            contract: { contract_template_id: template.id, content_override: '' } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('template', 'id')).to eq(template.id)
    expect(contract.reload.financial_summary).to eq(before)
    audit = JrcCrm::AuditEvent.where(account: account, resource_type: contract.class.name, resource_id: contract.id,
                                     event_type: 'contract_updated').last
    expect(audit.to_value['contract_template_id']).to eq(template.id)
    second = service.create!(idempotency_key: SecureRandom.uuid, expected_source_digest: service.source_digest(contract.id),
                             change_reason: 'TESTE SINTÉTICO — Modelo selecionado.')
    expect(second.snapshot.fetch('template')).to include('id' => template.id, 'body' => template.body)
    expect(Digest::SHA256.hexdigest(first.reload.pdf_blob.download)).to eq(first.pdf_sha256)
    expect(contract.signature_status).to eq('not_started')
  end

  it 'rejects foreign accounts, inactive templates and attempts to change financial terms' do
    foreign = create(:account).jrc_crm_contract_templates.create!(name: 'TESTE SINTÉTICO — Modelo externo', body: 'Texto')
    patch base, headers: headers, params: { expected_source_digest: JrcBackoffice::ContractSnapshot.digest(contract.reload),
                                            contract: { contract_template_id: foreign.id } }, as: :json
    expect(response).to have_http_status(:not_found)
    template.update!(active: false)
    patch base, headers: headers, params: { expected_source_digest: JrcBackoffice::ContractSnapshot.digest(contract.reload),
                                            contract: { contract_template_id: template.id } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    patch base, headers: headers, params: { expected_source_digest: JrcBackoffice::ContractSnapshot.digest(contract.reload),
                                            contract: { monthly_cents: 1, contract_template_id: template.id } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(contract.reload.contract_template_id).to be_nil
  end

  it 'keeps an inactive current model when editing another legal field and permits explicit use of a personal draft' do
    contract.update!(contract_template: template)
    template.update!(active: false)
    patch base, headers: headers, params: { expected_source_digest: JrcBackoffice::ContractSnapshot.digest(contract.reload),
                                            contract: { contract_template_id: template.id, notes: 'TESTE SINTÉTICO — Nota de revisão.' } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(contract.reload.contract_template_id).to eq(template.id)
    patch base, headers: headers, params: { expected_source_digest: JrcBackoffice::ContractSnapshot.digest(contract.reload),
                                            contract: { contract_template_id: nil,
                                                        content_override: 'TESTE SINTÉTICO — Minuta própria.' } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(contract.reload.contract_template_id).to be_nil
  end

  it 'does not bypass a stale preview or the sent contract boundary' do
    digest = JrcBackoffice::ContractSnapshot.digest(contract)
    contract.update!(notes: 'TESTE SINTÉTICO — Alteração concorrente.')
    patch base, headers: headers, params: { expected_source_digest: digest, contract: { contract_template_id: template.id } }, as: :json
    expect(response).to have_http_status(:conflict)
    contract.update!(signature_status: 'sent')
    get "#{base}/templates", headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.headers['Cache-Control']).to include('no-store')
    patch base, headers: headers, params: { expected_source_digest: JrcBackoffice::ContractSnapshot.digest(contract.reload),
                                            contract: { contract_template_id: template.id } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(contract.reload.contract_template_id).to be_nil
  end

  it 'denies unassigned and foreign actors and cannot change the issuer through query parameters' do
    agent = create(:user, account: account, role: :agent)
    get "#{base}/templates", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    foreign = create(:account)
    foreign_actor = create(:user, account: foreign, role: :administrator)
    get "#{base}/templates", headers: foreign_actor.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    template
    get "#{base}/templates", headers: headers, params: { account_id: foreign.id, unit_id: 999, company_id: 999 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['data'].pluck('id')).to eq([template.id])
  end

  it 'revalidates changed selection rules and refuses an old preview after the current legal model is edited' do
    get "#{base}/templates", headers: headers
    template.update!(selection_rules: { term_months: 36 })
    patch base, headers: headers, params: { expected_source_digest: JrcBackoffice::ContractSnapshot.digest(contract.reload),
                                            contract: { contract_template_id: template.id } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    contract.update!(contract_template: template)
    digest = JrcBackoffice::ContractSnapshot.digest(contract.reload)
    template.update!(body: 'TESTE SINTÉTICO — Cláusula alterada por outro editor.')
    patch base, headers: headers, params: { expected_source_digest: digest, contract: { notes: 'Tentativa com prévia antiga' } }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(contract.reload.notes).to be_blank
  end

  it 'filters legal text and free notes from the actual request log parameters while keeping the selected reference traceable' do
    patch base, headers: headers, params: { expected_source_digest: JrcBackoffice::ContractSnapshot.digest(contract.reload),
                                            contract: { contract_template_id: template.id,
                                                        content_override: 'TESTE SINTÉTICO — Texto jurídico reservado.',
                                                        notes: 'TESTE SINTÉTICO — Nota pessoal reservada.' } }, as: :json
    expect(response).to have_http_status(:ok)
    filtered = request.filtered_parameters.fetch('contract')
    expect(filtered.values_at('content_override', 'notes')).to eq(['[FILTERED]', '[FILTERED]'])
    expect(filtered['contract_template_id']).to eq(template.id)
    expect(contract.reload.notes).to eq('TESTE SINTÉTICO — Nota pessoal reservada.')
  end

  it 'allows the assigned CRM analyst to select an eligible model without granting template administration' do
    analyst = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: ['jrc_crm'])
    AccountUser.find_by!(account: account, user: analyst).update!(custom_role: role)
    account.jrc_crm_user_business_units.create!(user: analyst, scope: 'BUSINESS_UNIT', company: issuer, business_unit: unit,
                                                structure_managed: true, active: true)
    operation.update!(owner: analyst)
    template
    get "#{base}/templates", headers: analyst.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['data'].pluck('id')).to eq([template.id])
    patch base, headers: analyst.create_new_auth_token, params: {
      expected_source_digest: JrcBackoffice::ContractSnapshot.digest(contract.reload), contract: { contract_template_id: template.id }
    }, as: :json
    expect(response).to have_http_status(:ok)
    expect(contract.reload.contract_template_id).to eq(template.id)
  end

  it 'denies template lookup even for an administrator after its actual unit coverage is revoked' do
    operation
    template
    account.jrc_crm_user_business_units.where(user_id: actor.id).each { |coverage| coverage.update!(active: false) }
    get "#{base}/templates", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.body).not_to include(template.name, template.body)
    patch base, headers: headers, params: { expected_source_digest: JrcBackoffice::ContractSnapshot.digest(contract.reload),
                                            contract: { contract_template_id: template.id } }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(contract.reload.contract_template_id).to be_nil
  end
end
