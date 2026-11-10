require 'rails_helper'

RSpec.describe 'Customer economic groups', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:root) { "/api/v1/accounts/#{account.id}/customers/economic_groups" }
  let(:group) { JrcCustomers::EconomicGroup.create!(account: account, name: 'TESTE — Grupo corporativo') }

  before { account.enable_features!('jrc_customer_master', 'jrc_crm') }

  it 'creates and edits through authenticated routes, ignores ownership input and requires optimistic revision' do
    post root, headers: headers, params: { economic_group: { name: 'TESTE — Novo', account_id: 0, user_id: 0, unit_id: 0 } }, as: :json
    expect(response).to have_http_status(:created)
    record = JrcCustomers::EconomicGroup.find(response.parsed_body.dig('payload', 'id'))
    expect(record.account_id).to eq(account.id)
    patch "#{root}/#{record.id}", headers: headers, params: { economic_group: { description: 'Sem revisão' } }, as: :json
    expect(response).to have_http_status(:bad_request)
    patch "#{root}/#{record.id}", headers: headers,
                                  params: { economic_group: { description: 'Persistida', revision: record.updated_at.iso8601(6) } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(record.reload.description).to eq('Persistida')
  end

  it 'bounds group and member pages with disjoint IDs and treats wildcard searches literally' do
    26.times { |index| JrcCustomers::EconomicGroup.create!(account: account, name: format('TESTE — Catálogo %02d', index)) }
    get root, headers: headers, params: { page: 1, per_page: 25 }
    first = response.parsed_body
    expect(first['meta']).to include('total' => 26, 'per_page' => 25)
    get root, headers: headers, params: { page: 2, per_page: 25 }
    expect(response.parsed_body['payload'].pluck('id') & first['payload'].pluck('id')).to be_empty
    expect(response.parsed_body['payload'].size).to eq(1)
    get root, headers: headers, params: { q: '%' }
    expect(response.parsed_body['payload']).to be_empty
    get root, headers: headers, params: { per_page: 999 }
    expect(response.parsed_body.dig('meta', 'per_page')).to eq(50)
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'links with an explicit revision and returns paginated members with their real company IDs' do
    companies = Array.new(26) { |index| account.master_companies.create!(name: "TESTE — Integrante #{index}", economic_group: group.name) }
    get "#{root}/#{group.id}/members", headers: headers, params: { page: 2 }
    expect(response.parsed_body['meta']).to include('total' => 26, 'page' => 2)
    expect(response.parsed_body['payload'].size).to eq(1)
    expect(companies.map(&:id)).to include(response.parsed_body.dig('payload', 0, 'id'))
    post "#{root}/#{group.id}/assign", headers: headers, params: { company_id: companies.first.id, remove: true }, as: :json
    expect(response).to have_http_status(:bad_request)
    post "#{root}/#{group.id}/assign", headers: headers,
                                       params: { company_id: companies.first.id, company_revision: companies.first.updated_at.iso8601(6),
                                                 remove: true, account_id: 0, user_id: 0, unit_id: 0 }, as: :json
    expect(response).to have_http_status(:ok)
    expect(companies.first.reload.economic_group).to be_nil
  end

  it 'rejects another account group or principal and a revoked authenticated membership' do
    other = create(:account)
    foreign = JrcCustomers::EconomicGroup.create!(account: other, name: 'PRIVATE_FOREIGN_GROUP')
    company = other.master_companies.create!(name: 'PRIVATE_FOREIGN_COMPANY', economic_group: foreign.name)
    get "#{root}/#{foreign.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    patch "#{root}/#{group.id}", headers: headers,
                                 params: { economic_group: { principal_company_id: company.id, revision: group.updated_at.iso8601(6) } }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('PRIVATE_FOREIGN')
    AccountUser.find_by!(account: account, user: actor).destroy!
    get root, headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'allows existing directory agents to link visible companies but reserves group configuration to administrators' do
    agent = create(:user, account: account, role: :agent)
    agent_headers = agent.create_new_auth_token
    company = account.master_companies.create!(name: 'TESTE — Empresa da equipe')
    post root, headers: agent_headers, params: { economic_group: { name: 'TESTE — Restrito' } }, as: :json
    expect(response).to have_http_status(:unauthorized)
    post "#{root}/#{group.id}/assign", headers: agent_headers,
                                       params: { company_id: company.id, company_revision: company.updated_at.iso8601(6) }, as: :json
    expect(response).to have_http_status(:ok)
    expect(company.reload.economic_group).to eq(group.name)
  end

  it 'conceals scoped operators, their principal identity, unrelated snapshots and unit metadata' do
    visible = account.master_companies.create!(name: 'TESTE — Visível', economic_group: group.name)
    hidden = account.master_companies.create!(name: 'PRIVATE_OPERATOR', economic_group: group.name, relationship_type: 'internal')
    hidden_unit = account.jrc_crm_business_units.create!(name: 'PRIVATE_UNIT', code: 'PRIVATE', company_id: hidden.id)
    group.update!(principal_company_id: hidden.id)
    JrcCustomers::Audit.record!(account: account, actor: actor, resource: group, event_type: 'customer_economic_group_updated',
                                metadata: { token: 'PRIVATE_TOKEN', unit_id: hidden_unit.id }, to_value: { principal_company_id: hidden.id })
    get "#{root}/#{group.id}", headers: headers
    expect(response.parsed_body['payload']).to include('member_count' => 1, 'principal_company' => nil, 'can_manage' => false)
    get "#{root}/#{group.id}/members", headers: headers
    expect(response.parsed_body['payload'].pluck('id')).to eq([visible.id])
    get "#{root}/#{group.id}/history", headers: headers
    expect(response.body).not_to include('PRIVATE', 'principal_company_id', 'metadata', 'to_value')
    patch "#{root}/#{group.id}", headers: headers,
                                 params: { economic_group: { description: 'Forbidden', revision: group.updated_at.iso8601(6) } }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(JrcCrm::CorporateCoverage.new(account: account, user: actor).company_allowed?(hidden.id)).to be(false)
  end

  it 'rejects disabled access and custom roles without contact management' do
    role = create(:custom_role, account: account, permissions: ['conversation_manage'])
    AccountUser.find_by!(account: account, user: actor).update!(role: :agent, custom_role: role)
    get root, headers: headers
    expect(response).to have_http_status(:unauthorized)
    account.disable_features!('jrc_customer_master')
    get root, headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'omits groups occupied only by inaccessible operators from the catalog and metadata' do
    hidden = account.master_companies.create!(name: 'PRIVATE_OPERATOR_ONLY', relationship_type: 'internal', economic_group: 'PRIVATE_HIDDEN_GROUP')
    account.jrc_crm_business_units.create!(name: 'PRIVATE_UNIT_ONLY', code: 'PRIVATE-ONLY', company_id: hidden.id)
    hidden_group = JrcCustomers::EconomicGroup.find_by!(account: account, name: 'PRIVATE_HIDDEN_GROUP')
    get root, headers: headers
    expect(response.body).not_to include('PRIVATE_HIDDEN_GROUP')
    get "#{root}/#{hidden_group.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    get "/api/v1/accounts/#{account.id}/customers/metadata", headers: headers
    expect(response.parsed_body.fetch('economic_groups')).not_to include('PRIVATE_HIDDEN_GROUP')
  end

  it 'does not delete a populated group and requires confirmation for an unused group' do
    company = account.master_companies.create!(name: 'TESTE — Retida', economic_group: group.name)
    delete "#{root}/#{group.id}", headers: headers, params: { confirm: true, revision: group.updated_at.iso8601(6) }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(company.reload.economic_group).to eq(group.name)
    company.update!(economic_group: nil)
    delete "#{root}/#{group.id}", headers: headers, params: { revision: group.updated_at.iso8601(6) }, as: :json
    expect(response).to have_http_status(:bad_request)
    delete "#{root}/#{group.id}", headers: headers, params: { confirm: true, revision: group.updated_at.iso8601(6) }, as: :json
    expect(response).to have_http_status(:no_content)
  end
end
