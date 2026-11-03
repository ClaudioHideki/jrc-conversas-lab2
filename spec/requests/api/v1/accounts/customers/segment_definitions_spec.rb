require 'rails_helper'

RSpec.describe 'Corporate customer segment definitions', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:root) { "/api/v1/accounts/#{account.id}/customers" }
  let(:taxonomy) { JrcCustomers::Taxonomy.create!(account: account, kind: 'segment', name: 'TESTE — Segmento API') }

  before { account.enable_features!('jrc_customer_master') }

  it 'previews a proposal without persisting it and enforces bounded pages and no-store' do
    account.master_companies.create!(name: 'TESTE — Cliente', relationship_type: 'customer')
    account.master_companies.create!(name: 'TESTE — Prospect', relationship_type: 'prospect')
    expect do
      post "#{root}/taxonomies/preview", headers: headers, params: { taxonomy: {
        name: 'TESTE — Prévia', kind: 'segment', selection_mode: 'dynamic', criteria: { match: 'all', rules: [
          { field: 'relationship_type', operator: 'equal_to', value: 'customer' }
        ] }
      }, per_page: 1000 }, as: :json
    end.not_to change(JrcCustomers::Taxonomy, :count)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('counts', 'companies')).to eq(1)
    expect(response.parsed_body.dig('meta', 'per_page')).to eq(50)
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'uses the same computed membership in company and person directory filters' do
    company = account.master_companies.create!(name: 'TESTE — Dentro', segment: taxonomy.name)
    person = create(:contact, account: account, company_id: company.id)
    account.master_companies.create!(name: 'TESTE — Fora')
    get "#{root}/companies", headers: headers, params: { taxonomy_id: taxonomy.id }
    expect(response.parsed_body['payload'].pluck('id')).to eq([company.id])
    get "#{root}/contacts", headers: headers, params: { taxonomy_id: taxonomy.id }
    expect(response.parsed_body['payload'].pluck('id')).to eq([person.id])
  end

  it 'previews and atomically creates manual choices from the wizard without changing the original company' do
    company = account.master_companies.create!(name: 'TESTE — Inclusão manual')
    definition = { kind: 'segment', name: 'TESTE — Assistente', manual_choices: [
      { subject_kind: 'companies', subject_id: company.id, mode: 'include' }
    ] }
    post "#{root}/taxonomies/preview", headers: headers, params: { taxonomy: definition }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload'].pluck('id')).to eq([company.id])
    post "#{root}/taxonomies", headers: headers, params: { taxonomy: definition }, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.dig('payload', 'id')
    expect(JrcCustomers::SegmentOverride.find_by!(taxonomy_id: id, company_id: company.id).mode).to eq('include')
    expect(company.reload.segment).to be_blank
    get "#{root}/taxonomies/#{id}/members", headers: headers
    expect(response.parsed_body['payload'].pluck('id')).to eq([company.id])
  end

  it 'retains saved manual choices during an unsaved criteria preview and rolls back invalid wizard submissions' do
    company = account.master_companies.create!(name: 'TESTE — Manual salvo')
    JrcCustomers::SegmentOverride.create!(account: account, taxonomy: taxonomy, company: company, mode: 'include')
    post "#{root}/taxonomies/preview", headers: headers, params: { taxonomy_id: taxonomy.id, taxonomy: {
      kind: 'segment', name: taxonomy.name, selection_mode: 'dynamic', criteria: { match: 'all', rules: [
        { field: 'active', operator: 'equal_to', value: 'false' }
      ] }
    } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload'].pluck('id')).to eq([company.id])
    expect(taxonomy.reload.selection_mode).to eq('classification')
    foreign = create(:account).master_companies.create!(name: 'TESTE — Fora')
    expect do
      post "#{root}/taxonomies", headers: headers, params: { taxonomy: { kind: 'segment', name: 'TESTE — Recusar', manual_choices: [
        { subject_kind: 'companies', subject_id: foreign.id, mode: 'include' }
      ] } }, as: :json
    end.not_to change(JrcCustomers::Taxonomy, :count)
    expect(response).to have_http_status(:not_found)
  end

  it 'returns non-overlapping stable result pages and rejects malformed or unauthorized criteria' do
    3.times { |index| account.master_companies.create!(name: "TESTE — Página #{index}", segment: taxonomy.name) }
    get "#{root}/taxonomies/#{taxonomy.id}/members", headers: headers, params: { per_page: 2 }
    first_ids = response.parsed_body['payload'].pluck('id')
    expect(response.parsed_body.dig('meta', 'total')).to eq(3)
    get "#{root}/taxonomies/#{taxonomy.id}/members", headers: headers, params: { per_page: 2, page: 2 }
    expect(response.parsed_body['payload'].pluck('id') & first_ids).to be_empty
    expect(response.parsed_body['payload'].size).to eq(1)
    post "#{root}/taxonomies/preview", headers: headers, params: { taxonomy: {
      kind: 'segment', name: 'TESTE — Recusar campo', selection_mode: 'dynamic', criteria: { match: 'all', rules: [
        { field: 'account_id', operator: 'equal_to', value: account.id.to_s }
      ] }
    } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'does not fetch another tenant segment through any member endpoint or filter' do
    foreign = JrcCustomers::Taxonomy.create!(account: create(:account), kind: 'segment', name: 'TESTE — Outro tenant')
    %w[members overrides history].each do |action|
      get "#{root}/taxonomies/#{foreign.id}/#{action}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
    get "#{root}/companies", headers: headers, params: { taxonomy_id: foreign.id }
    expect(response).to have_http_status(:not_found)
  end

  it 'requires native permission, protects administrator writes and ignores caller account/user fields' do
    agent = create(:user, account: account, role: :agent)
    post "#{root}/taxonomies", headers: agent.create_new_auth_token, params: { taxonomy: { kind: 'segment', name: 'Denied' } }, as: :json
    expect(response).to have_http_status(:unauthorized)
    post "#{root}/taxonomies", headers: headers, params: { taxonomy: { kind: 'segment', name: 'TESTE — Criado', account_id: 0, user_id: 0 } },
                               as: :json
    expect(response).to have_http_status(:created)
    expect(JrcCustomers::Taxonomy.find(response.parsed_body.dig('payload', 'id')).account_id).to eq(account.id)
    account.disable_features!('jrc_customer_master')
    get "#{root}/taxonomies/#{taxonomy.id}/members", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'paginates manual choices and history and refuses destructive deletion with dependencies' do
    company = account.master_companies.create!(name: 'TESTE — Escolha')
    post "#{root}/taxonomies/#{taxonomy.id}/set_override", headers: headers,
                                                           params: { subject_kind: 'companies', subject_id: company.id, mode: 'include' }, as: :json
    expect(response).to have_http_status(:ok)
    get "#{root}/taxonomies/#{taxonomy.id}/overrides", headers: headers, params: { per_page: 1 }
    expect(response.parsed_body.dig('meta', 'total')).to eq(1)
    get "#{root}/taxonomies/#{taxonomy.id}/history", headers: headers
    expect(response.parsed_body['payload'].first['kind']).to eq('customer_segment_override_changed')
    expect(response.parsed_body['payload'].first.keys).not_to include('metadata', 'from_value', 'to_value')
    delete "#{root}/taxonomies/#{taxonomy.id}", headers: headers, params: { confirm: true }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
