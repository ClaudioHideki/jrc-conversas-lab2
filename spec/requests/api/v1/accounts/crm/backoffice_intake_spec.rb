require 'rails_helper'

RSpec.describe 'Backoffice canonical customer intake', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:company) { account.master_companies.create!(name: 'TESTE SINTÉTICO — Cliente canônico') }
  let(:contact) { create(:contact, account: account, company_id: company.id) }
  let(:order) { account.jrc_crm_sales_orders.create!(owner: admin, contact: contact, status: 'approved') }
  let(:base) { "/api/v1/accounts/#{account.id}/crm/backoffice_requests" }

  before { account.enable_features!('jrc_crm', 'jrc_customer_master') }

  it 'searches the complete authorized master directory independently of the loaded page' do
    21.times { |index| account.master_companies.create!(name: "TESTE SINTÉTICO — Cliente #{index}") }
    expected = account.master_companies.create!(name: 'TESTE SINTÉTICO — ZULU busca completa')
    get "/api/v1/accounts/#{account.id}/customers/companies", params: { q: 'ZULU', page: 1, per_page: 20 }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([expected.id])
  end

  it 'paginates only the chosen company orders, never a same-name company or another account' do
    expected = [order]
    2.times { expected << account.jrc_crm_sales_orders.create!(owner: admin, contact: contact, status: 'approved') }
    other_company = account.master_companies.create!(name: company.name)
    other_contact = create(:contact, account: account, company_id: other_company.id)
    account.jrc_crm_sales_orders.create!(owner: admin, contact: other_contact, status: 'approved')
    get "#{base}/order_options", params: { company_id: company.id, kind: 'change', page: 2, per_page: 1 }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('meta')).to include('page' => 2, 'per_page' => 1, 'total' => 3)
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([expected[1].id])
    expect(response.parsed_body.fetch('payload').first.keys).to match_array(%w[id order_number status contact])
  end

  it 'keeps a customer without an order in the master directory and returns an empty order selection' do
    get "#{base}/order_options", params: { company_id: company.id, kind: 'change' }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('payload' => [], 'meta' => { 'page' => 1, 'per_page' => 20, 'total' => 0 })
  end

  it 'rejects a foreign company identifier without returning its records' do
    foreign = create(:account).master_companies.create!(name: 'TESTE SINTÉTICO — outra conta')
    get "#{base}/order_options", params: { company_id: foreign.id, kind: 'change' }, headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'does not grant order access by submitting a company identifier from the current account' do
    foreign = create(:account)
    foreign_owner = create(:user, account: foreign, role: :administrator)
    foreign_order = foreign.jrc_crm_sales_orders.create!(owner: foreign_owner, status: 'approved')
    post base, params: { company_id: company.id, backoffice_request: { sales_order_id: foreign_order.id,
                                                                       request_kind: 'change', title: 'TESTE SINTÉTICO — negado' } },
               headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(account.jrc_crm_backoffice_requests).not_to exist
  end

  it 'keeps the organizational coverage on order options even for an administrator' do
    issuer = account.master_companies.create!(name: 'TESTE SINTÉTICO — Operadora A', relationship_type: 'internal')
    other_issuer = account.master_companies.create!(name: 'TESTE SINTÉTICO — Operadora B', relationship_type: 'internal')
    unit = account.jrc_crm_business_units.create!(name: 'TESTE SINTÉTICO — Unidade A', code: 'intake-a', company_id: issuer.id)
    other_unit = account.jrc_crm_business_units.create!(name: 'TESTE SINTÉTICO — Unidade B', code: 'intake-b', company_id: other_issuer.id)
    JrcCrm::UserBusinessUnit.create!(account: account, user: admin, business_unit: unit, scope: 'BUSINESS_UNIT', structure_managed: true)
    allowed = account.jrc_crm_sales_orders.create!(owner: admin, contact: contact, business_unit: unit, status: 'approved')
    account.jrc_crm_sales_orders.create!(owner: admin, contact: contact, business_unit: other_unit, status: 'approved')
    get "#{base}/order_options", params: { company_id: company.id, kind: 'change' }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([allowed.id])
  end

  it 'requires both CRM and the master-directory permission on the server' do
    account.disable_features!('jrc_customer_master')
    get "#{base}/order_options", params: { company_id: company.id, kind: 'change' }, headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'does not offer a draft order or an existing fulfillment for a new fulfillment request' do
    order
    account.jrc_crm_sales_orders.create!(owner: admin, contact: contact, status: 'draft')
    order.backoffice_requests.create!(account: account, owner: admin, requested_by: admin, contact: contact,
                                      title: 'TESTE SINTÉTICO — Operação existente', request_kind: 'fulfillment')
    get "#{base}/order_options", params: { company_id: company.id, kind: 'fulfillment' }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload')).to eq([])
  end

  it 'rejects a forged company/order pair instead of relinking the order' do
    wrong = account.master_companies.create!(name: 'TESTE SINTÉTICO — Cliente incorreto')
    post base, params: { company_id: wrong.id, backoffice_request: { sales_order_id: order.id, request_kind: 'change', title: 'TESTE SINTÉTICO' } },
               headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(order.backoffice_requests.where(request_kind: 'change')).not_to exist
    expect(order.reload.contact.company_id).to eq(company.id)
  end

  it 'checks eligibility again at creation instead of trusting an earlier selection' do
    draft = account.jrc_crm_sales_orders.create!(owner: admin, contact: contact, status: 'draft')
    post base, params: { company_id: company.id, backoffice_request: { sales_order_id: draft.id, request_kind: 'fulfillment',
                                                                       title: 'TESTE SINTÉTICO — não elegível' } }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(draft.backoffice_requests).not_to exist
  end

  it 'creates, lists and reopens Alteração with the same canonical customer, order and account, preserving legacy workflow' do
    post base, params: { company_id: company.id, backoffice_request: { sales_order_id: order.id, request_kind: 'change',
                                                                       title: 'TESTE SINTÉTICO — Alteração' } }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    record = account.jrc_crm_backoffice_requests.find(response.parsed_body.fetch('id'))
    expect(record.attributes).to include('account_id' => account.id, 'sales_order_id' => order.id, 'contact_id' => contact.id,
                                         'workflow_version' => 1)
    get base, headers: headers
    expect(response.parsed_body.pluck('id')).to include(record.id)
    record.update!(status: 'canceled')
    post "#{base}/#{record.id}/reopen", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    get "#{base}/#{record.id}", headers: headers
    expect(response.parsed_body).to include('id' => record.id, 'workflow_version' => 1, 'company' => { 'id' => company.id, 'name' => company.name })
    expect(response.parsed_body.dig('order', 'id')).to eq(order.id)
  end
end
