require 'rails_helper'

RSpec.describe 'Company contact context', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :agent) }
  let(:headers) { actor.create_new_auth_token }
  let(:company) { account.master_companies.create!(name: 'TESTE SINTÉTICO — Cliente do vínculo') }
  let(:contact) { create(:contact, account: account, company_id: company.id) }
  let(:root) { "/api/v1/accounts/#{account.id}/customers/contacts" }

  before { account.enable_features!('jrc_crm', 'jrc_customer_master') }

  it 'uses the authenticated account and supports confirmed primary replacement through the existing update endpoint' do
    previous = create(:contact, account: account, company_id: company.id, company_primary: true)
    values = { contact: { company_primary: true, company_role: 'technical', account_id: 0, user_id: 0, unit_id: 0 } }
    patch "#{root}/#{contact.id}", headers: headers, params: values, as: :json
    expect(response).to have_http_status(:conflict)
    expect(previous.reload.company_primary?).to be(true)
    patch "#{root}/#{contact.id}", headers: headers, params: values.merge(confirm_primary_change: true), as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload']).to include('id' => contact.id, 'company_role' => 'technical', 'company_primary' => true)
    expect(previous.reload.company_primary?).to be(false)
    expect(contact.reload.account_id).to eq(account.id)
  end

  it 'returns real link history with server paging and omits unrelated audit snapshots and identifiers' do
    26.times do
      JrcCustomers::Audit.record!(account: account, actor: actor, resource: contact, event_type: 'customer_contact_linked',
                                  from_value: { company_id: nil },
                                  to_value: { company_id: company.id, company_role: 'finance', email: 'PRIVATE_EMAIL', token: 'PRIVATE_TOKEN' })
    end
    get "#{root}/#{contact.id}/company_history", headers: headers, params: { page: 1, account_id: 0, contact_id: 0, user_id: 0 }
    expect(response).to have_http_status(:ok)
    first = response.parsed_body
    expect(first['meta']).to include('total' => 26, 'per_page' => 25, 'page' => 1)
    expect(first['payload'].size).to eq(25)
    expect(response.body).not_to include('PRIVATE_EMAIL', 'PRIVATE_TOKEN', 'metadata', 'from_value', 'to_value')
    expect(response.headers['Cache-Control']).to include('no-store')
    get "#{root}/#{contact.id}/company_history", headers: headers, params: { page: 2 }
    expect(response.parsed_body['payload'].size).to eq(1)
    expect(response.parsed_body['payload'].pluck('id') & first['payload'].pluck('id')).to be_empty
  end

  it 'caps a requested page size while preserving the total of the authorized history' do
    51.times do
      JrcCustomers::Audit.record!(account: account, actor: actor, resource: contact, event_type: 'customer_contact_linked',
                                  to_value: { company_id: company.id })
    end
    get "#{root}/#{contact.id}/company_history", headers: headers, params: { per_page: 999 }
    expect(response.parsed_body['meta']).to include('per_page' => 50, 'total' => 51)
    expect(response.parsed_body['payload'].size).to eq(50)
  end

  it 'conceals the previous company context after its operator or unit coverage is withdrawn' do
    issuer = account.master_companies.create!(name: 'TESTE SINTÉTICO — Operadora permitida', relationship_type: 'internal')
    hidden = account.master_companies.create!(name: 'PRIVATE_HIDDEN_OPERATOR', relationship_type: 'internal')
    unit = account.jrc_crm_business_units.create!(name: 'TESTE SINTÉTICO — Unidade permitida', code: 'CTX-A', company_id: issuer.id)
    account.jrc_crm_business_units.create!(name: 'PRIVATE_HIDDEN_UNIT', code: 'CTX-B', company_id: hidden.id)
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: issuer, business_unit: unit, active: true)
    JrcCustomers::Audit.record!(account: account, actor: actor, resource: contact, event_type: 'customer_contact_linked',
                                from_value: { company_id: hidden.id, company_role: 'executive', job_title: 'PRIVATE_HIDDEN_JOB' },
                                to_value: { company_id: company.id, company_role: 'finance' })
    get "#{root}/#{contact.id}/company_history", headers: headers, params: { unit_id: 0, operator_id: hidden.id }
    expect(response).to have_http_status(:ok)
    row = response.parsed_body['payload'].first
    expect(row['from']).to eq('restricted' => true)
    expect(row['to']).to include('company_name' => company.name, 'company_role' => 'finance')
    expect(response.body).not_to include('PRIVATE_HIDDEN', 'executive')
    hidden_person = create(:contact, account: account, company_id: hidden.id)
    patch "#{root}/#{hidden_person.id}", headers: headers, params: { contact: { company_primary: true }, unit_id: unit.id }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(hidden_person.reload.company_primary?).to be(false)
  end

  it 'rejects another account and revalidates native directory permissions on history and writes' do
    foreign = create(:contact)
    get "#{root}/#{foreign.id}/company_history", headers: headers
    expect(response).to have_http_status(:not_found)
    role = create(:custom_role, account: account, permissions: %w[jrc_crm])
    account.account_users.find_by!(user: actor).update!(custom_role: role)
    get "#{root}/#{contact.id}/company_history", headers: headers
    expect(response).to have_http_status(:unauthorized)
    patch "#{root}/#{contact.id}", headers: headers, params: { contact: { company_primary: true } }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(contact.reload.company_primary?).to be(false)
  end
end
