require 'rails_helper'

RSpec.describe 'Versioned monthly proposal requests', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:company) { account.master_companies.create!(name: 'Synthetic recurring customer', tax_id: '11222333000181') }
  let(:contact) { create(:contact, account: account, company_id: company.id, name: 'Synthetic requester') }
  let(:product) { JrcCrm::Product.create!(account: account, name: 'Monthly service', sku: 'SYN-MONTHLY', billing_model: 'monthly', unit_price_cents: 29_500, active: true) }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/proposals" }
  let(:payload) do
    { company_id: company.id, contact_id: contact.id,
      proposal: { title: '36 monthly periods', term_months: 36, installments_count: 36, payment_condition: 'installments' },
      items: [{ product_id: product.id, quantity: 1, unit_price_cents: 29_500 }] }
  end
  before { account.enable_features!('jrc_crm', 'jrc_customer_master') }

  let(:legacy_proposal) do
    proposal = JrcCrm::Proposal.create!(account: account, owner: admin, company: company, contact: contact,
      title: 'Legacy approved monthly service', financial_version: 2, term_months: 36,
      payment_condition: 'installments', installments_count: 36,
      status: 'draft', approval_status: 'approved', commercial_approval_status: 'approved')
    proposal.proposal_items.create!(product: product, name_snapshot: product.name, quantity: 1, unit_price_cents: 29_500, billing_model: 'monthly')
    proposal
  end

  it 'recalculates an approved but unsent legacy proposal only when its owner explicitly saves unchanged terms' do
    original = legacy_proposal.reload.attributes
    get "#{base}/#{legacy_proposal.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['financial_version']).to eq(2)
    expect(legacy_proposal.reload.attributes).to eq(original)

    expect do
      patch "#{base}/#{legacy_proposal.id}",
            params: { proposal: { term_months: 36, installments_count: 36, payment_condition: 'installments' } },
            headers: headers, as: :json
    end.not_to change(Message, :count)
    expect(response).to have_http_status(:ok), response.body
    expect(legacy_proposal.reload).to have_attributes(financial_version: 3, monthly_cents: 29_500,
                                                    status: 'draft', approval_status: 'not_required', sent_at: nil)
    expect(response.parsed_body).to include('installment_plan_cents' => [], 'recurring_months_count' => 36,
                                           'recurring_total_cents' => 1_062_000, 'contract_total_cents' => 1_062_000)
  end

  it 'preserves already sent legacy financial terms even when the authorized owner saves unchanged terms' do
    legacy_proposal.update!(sent_at: Time.current, status: 'sent')
    patch "#{base}/#{legacy_proposal.id}",
          params: { proposal: { term_months: 36, installments_count: 36, payment_condition: 'installments' } },
          headers: headers, as: :json
    expect(response).to have_http_status(:ok), response.body
    expect(legacy_proposal.reload).to have_attributes(financial_version: 2, status: 'sent')
    expect(response.parsed_body['installment_plan_cents'].sum).to eq(29_500)
  end

  it 'persists the correct terms and serves the same values in the API and real PDF' do
    post base, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:created), response.body
    data = response.parsed_body
    proposal = JrcCrm::Proposal.find(data.fetch('id'))
    expect(proposal).to have_attributes(financial_version: 3, monthly_cents: 29_500, total_cents: 29_500, term_months: 36)
    expect(data).to include('installment_plan_cents' => [], 'recurring_months_count' => 36, 'recurring_total_cents' => 1_062_000,
                           'contract_total_cents' => 1_062_000, 'total_first_month_cents' => 29_500)
    get "#{base}/#{proposal.id}/pdf", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body.b).to start_with('%PDF-')
    expect(response.body.b).to include('36 mensalidades de R$ 295,00', 'R$ 10.620,00')
    expect(response.body.b).not_to include('R$ 8,20', 'R$ 8,19')
  end

  it 'renders the public proposal terms without triggering transport delivery' do
    post base, params: payload, headers: headers, as: :json
    proposal = JrcCrm::Proposal.find(response.parsed_body.fetch('id'))
    proposal.update!(sent_at: Time.current, status: 'sent')
    expect do
      get "/jrc/propostas/#{account.id}/#{proposal.public_token}"
    end.not_to change(Message, :count)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('36 mensalidades de', 'R$ 295,00', 'R$ 10.620,00')
  end

  it 'preserves previously published version 2 values and rejects cross-Account changes' do
    historical = JrcCrm::Proposal.create!(account: account, owner: admin, company: company, contact: contact,
      title: 'Historical subscription', financial_version: 2, term_months: 36, payment_condition: 'installments', installments_count: 36)
    historical.proposal_items.create!(product: product, name_snapshot: product.name, quantity: 1, unit_price_cents: 29_500, billing_model: 'monthly')
    historical.update!(sent_at: Time.current, status: 'sent')
    original = historical.reload.attributes
    get "#{base}/#{historical.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['financial_version']).to eq(2)
    expect(response.parsed_body['installment_plan_cents'].sum).to eq(29_500)
    expect(historical.reload.attributes).to eq(original)
    foreign = create(:user, account: create(:account), role: :administrator)
    patch "#{base}/#{historical.id}", params: { proposal: { term_months: 12 } }, headers: foreign.create_new_auth_token, as: :json
    expect(response.status).to be_in([401, 403, 404])
    expect(historical.reload.attributes).to eq(original)
  end

  it 'carries the 36 monthly fees into the order and frozen contract PDF without changing approval gates' do
    post base, params: payload, headers: headers, as: :json
    proposal = JrcCrm::Proposal.find(response.parsed_body.fetch('id'))
    create(:conversation, account: account, contact: contact)
    post "#{base}/#{proposal.id}/send_proposal", headers: headers, as: :json
    expect(response).to have_http_status(:ok), response.body.first(600)
    proposal.reload.accept_by_customer!(name: 'Synthetic signer', document: 'synthetic-document', remote_ip: '127.0.0.1', user_agent: 'isolated request test')
    order = JrcCrm::ProposalToOrderService.new(proposal: proposal, actor: admin).call
    expect(order.reload.financial_summary).to include(financial_version: 3, recurring_total_cents: 1_062_000, contract_total_cents: 1_062_000,
                                                    one_time_total_cents: 0, installment_plan_cents: [])
    expect(JrcCrm::OrderContractService.new(order: order, actor: admin).call).to be_nil
    template = JrcCrm::ContractTemplate.create!(account: account, name: 'Synthetic monthly terms', body: 'Total {{ valor_total }}. Mensal {{ valor_mensal }}. Prazo {{ quantidade_mensalidades }}.', variables: {})
    approval = order.backoffice_requests.find_by!(request_kind: 'approval')
    post "/api/v1/accounts/#{account.id}/crm/backoffice_requests/#{approval.id}/decide_order",
         params: { decision: 'approved' }, headers: headers, as: :json
    expect(response).to have_http_status(:ok), response.body.first(600)
    expect(order.reload).to be_approved
    contract = JrcCrm::OrderContractService.new(order: order, actor: admin).call
    expect(contract).to have_attributes(term_months: 36, monthly_cents: 29_500)
    expect(contract.financial_summary).to include('financial_version' => 3, 'recurring_total_cents' => 1_062_000)
    expect(contract.contract_template_id).to eq(template.id)
    pdf = JrcCrm::ContractPdfService.new(contract).call
    expect(pdf.b).to include('R$ 10.620,00', 'R$ 295,00')
    expect(pdf.b).not_to include('R$ 8,20')
    expect(JrcCrm::CommercialDocumentService.new(kind: :contract, record: contract).send(:clauses).join(' ')).to include('Total R$ 10.620,00', 'Prazo 36')
  end
end
