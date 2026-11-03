require 'rails_helper'

RSpec.describe 'Static classifications and dynamic directory filters', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:root) { "/api/v1/accounts/#{account.id}/customers" }
  let(:classification) { JrcCustomers::Taxonomy.create!(account: account, kind: 'segment', name: 'TESTE — Classificação') }
  let(:criteria) { { match: 'all', rules: [{ field: 'active', operator: 'equal_to', value: 'true' }] } }
  let!(:dynamic) do
    JrcCustomers::Taxonomy.create!(account: account, kind: 'segment', name: 'TESTE — Filtro dinâmico', selection_mode: 'dynamic', criteria: criteria)
  end

  before { account.enable_features!('jrc_customer_master') }

  it 'keeps only active static classifications in the company editor metadata' do
    classification
    JrcCustomers::Taxonomy.create!(account: account, kind: 'segment', name: 'TESTE — Inativo', active: false)
    JrcCustomers::Taxonomy.create!(account: create(:account), kind: 'segment', name: 'TESTE — Outro tenant')
    get "#{root}/metadata", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['segments']).to eq([classification.name])
  end

  it 'does not treat a dynamic definition as a direct company classification' do
    expect do
      post "#{root}/companies", headers: headers, params: { company: { name: 'TESTE — Recusar classificação', segment: dynamic.name } }, as: :json
    end.not_to change(JrcCustomers::Company, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    post "#{root}/companies", headers: headers, params: { company: { name: 'TESTE — Classificação válida', segment: classification.name } }, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig('payload', 'segment')).to eq(classification.name)
  end

  it 'preserves an existing assigned classification instead of changing its selection semantics' do
    company = account.master_companies.create!(name: 'TESTE — Empresa classificada', segment: classification.name)
    revision = classification.updated_at.iso8601(6)
    patch "#{root}/taxonomies/#{classification.id}", headers: headers, params: { taxonomy: {
      selection_mode: 'dynamic', criteria: criteria, revision: revision
    } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(classification.reload.selection_mode).to eq('classification')
    expect(classification.updated_at.iso8601(6)).to eq(revision)
    expect(company.reload.segment).to eq(classification.name)
    expect(JrcCrm::AuditEvent.where(account: account, resource_type: 'JrcCustomers::Taxonomy', resource_id: classification.id)).to be_empty
  end

  it 'allows the explicit conversion of an unused definition and removes it from the static selector' do
    patch "#{root}/taxonomies/#{classification.id}", headers: headers, params: { taxonomy: {
      selection_mode: 'dynamic', criteria: criteria, revision: classification.updated_at.iso8601(6)
    } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(classification.reload.selection_mode).to eq('dynamic')
    get "#{root}/metadata", headers: headers
    expect(response.parsed_body['segments']).not_to include(classification.name)
  end

  it 'searches literal names with bounded stable paging and excludes inactive and foreign definitions' do
    records = Array.new(3) { |index| JrcCustomers::Taxonomy.create!(account: account, kind: 'segment', name: "TESTE — Busca %_#{index}") }
    JrcCustomers::Taxonomy.create!(account: account, kind: 'segment', name: 'TESTE — Busca %_inativa', active: false)
    JrcCustomers::Taxonomy.create!(account: create(:account), kind: 'segment', name: 'TESTE — Busca %_fora')
    get "#{root}/taxonomies", headers: headers, params: { q: 'Busca %_', active: true, per_page: 2 }
    expect(response.parsed_body.dig('meta', 'total')).to eq(3)
    first_ids = response.parsed_body['payload'].pluck('id')
    expect(first_ids).to eq(records.first(2).map(&:id))
    get "#{root}/taxonomies", headers: headers, params: { q: 'Busca %_', active: true, per_page: 2, page: 2 }
    expect(response.parsed_body['payload'].pluck('id')).to eq([records.last.id])
    expect(response.parsed_body['payload'].pluck('id') & first_ids).to be_empty
  end

  it 'does not retain errors from a refused mode change when editing allowed metadata afterwards' do
    account.master_companies.create!(name: 'TESTE — Empresa preservada', segment: classification.name)
    writer = JrcCustomers::TaxonomyWriter.new(account: account, actor: admin)
    expect { writer.save!(taxonomy: classification, attributes: { selection_mode: 'dynamic', criteria: criteria }) }
      .to raise_error(ActiveRecord::RecordInvalid)
    writer.save!(taxonomy: classification, attributes: { description: 'TESTE — Descrição permitida' })
    expect(classification.reload.description).to eq('TESTE — Descrição permitida')
    expect(classification.selection_mode).to eq('classification')
  end

  it 'does not interpret object-shaped query fields or caller account identifiers as lookup authority' do
    foreign = JrcCustomers::Taxonomy.create!(account: create(:account), kind: 'segment', name: 'TESTE — Outro tenant')
    get "#{root}/taxonomies", headers: headers, params: { q: { value: 'private' }, active: { value: 'false' }, account_id: foreign.account_id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload'].pluck('id')).to eq([dynamic.id])
    expect(response.parsed_body.dig('meta', 'per_page')).to eq(25)
  end
end
