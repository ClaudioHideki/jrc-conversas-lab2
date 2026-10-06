require 'rails_helper'

RSpec.describe 'CRM deal and master contact creation homologation', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:headers) { agent.create_new_auth_token }
  let(:company) { account.master_companies.create!(name: 'Empresa de homologação') }
  let(:contact) { create(:contact, account: account, company_id: company.id, name: 'Contato vinculado', email: 'vinculado@example.test') }
  let(:pipeline) { JrcCrm::DefaultPipelineService.new(account).perform }
  let(:product) { account.jrc_crm_products.create!(name: 'Serviço', sku: 'NATIVE-01', active: true, unit_price_cents: 10_000) }
  let(:attributes) { { title: 'Negócio com rascunho', company_id: company.id, contact_id: contact.id, pipeline_id: pipeline.id,
                      stage_id: pipeline.stages.active.order(:position).first.id, description: 'Preservar notas' } }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/deals" }
  before { account.enable_features!('jrc_crm', 'jrc_customer_master') }

  it 'saves deal, products and next agenda activity as one successful creation' do
    post url, headers: headers, as: :json, params: { deal: attributes,
      items: [{ product_id: product.id, quantity: 2, unit_price_cents: 10_000, discount_cents: 1000 }],
      next_activity: { title: 'Retorno', activity_type: 'call', due_at: 1.day.from_now.iso8601 } }
    expect(response).to have_http_status(:created)
    deal = JrcCrm::Deal.find(response.parsed_body['id'])
    expect(deal.value_cents).to eq(19_000)
    expect(deal.deal_products.count).to eq(1)
    expect(deal.activities.pluck(:title)).to eq(['Retorno'])
    expect(deal.activities.first.user_id).to eq(agent.id)
  end

  it 'rolls back the entire creation if an item fails, so a retained draft can be retried safely' do
    expect {
      post url, headers: headers, as: :json, params: { deal: attributes,
        items: [{ product_id: product.id, quantity: 0, unit_price_cents: 10_000, discount_cents: 0 }] }
    }.not_to change(JrcCrm::Deal, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'rolls back the entire creation if the next activity fails' do
    expect {
      post url, headers: headers, as: :json, params: { deal: attributes,
        next_activity: { title: '', activity_type: 'call', due_at: 1.day.from_now.iso8601 } }
    }.not_to change(JrcCrm::Deal, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'rejects a product belonging to another account without leaving an incomplete deal' do
    outsider = JrcCrm::Product.create!(account: create(:account), name: 'Não permitido', sku: 'OTHER', active: true, unit_price_cents: 1000)
    expect {
      post url, headers: headers, as: :json, params: { deal: attributes,
        items: [{ product_id: outsider.id, quantity: 1, unit_price_cents: 1000, discount_cents: 0 }] }
    }.not_to change(JrcCrm::Deal, :count)
    expect(response).to have_http_status(:not_found)
  end

  it 'DEAL-03 creates the inline contact in the same official master contact table' do
    expect {
      post "/api/v1/accounts/#{account.id}/customers/contacts", headers: headers, as: :json,
        params: { contact: { name: 'Novo contato', email: 'novo-inline@example.test', company_id: company.id, job_title: 'Comprador' } }
    }.to change(Contact, :count).by(1)
    expect(response).to have_http_status(:created)
    created = Contact.find(response.parsed_body.dig('payload', 'id'))
    expect(created.account_id).to eq(account.id)
    expect(created.company_id).to eq(company.id)
  end

  it 'DEAL-01/ACCOUNT-01 finds contacts through their official company and excludes another tenant' do
    contact
    create(:contact, name: 'Outro tenant', email: 'other@example.test')
    get "/api/v1/accounts/#{account.id}/customers/contacts", params: { q: company.name, per_page: 15 }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload'].pluck('id')).to eq([contact.id])
    expect(response.parsed_body.dig('meta', 'per_page')).to eq(15)
  end
end
