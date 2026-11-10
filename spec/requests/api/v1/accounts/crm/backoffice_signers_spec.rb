require 'rails_helper'

RSpec.describe 'Backoffice canonical signer API', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:customer) { account.master_companies.create!(name: 'TESTE SINTÉTICO — Cliente API', relationship_type: 'customer') }
  let(:issuer) { account.master_companies.create!(name: 'TESTE SINTÉTICO — Emitente API', relationship_type: 'internal') }
  let(:unit) { account.jrc_crm_business_units.create!(name: 'TESTE SINTÉTICO — Unidade API', code: 'SIGNERS-API', company_id: issuer.id) }
  let(:customer_person) { create(:contact, account: account, company_id: customer.id, email: 'customer.api@example.test') }
  let(:issuer_person) { create(:contact, account: account, company_id: issuer.id, email: 'issuer.api@example.test') }
  let(:order) { account.jrc_crm_sales_orders.create!(owner: actor, contact: customer_person, business_unit: unit, status: 'approved') }
  let(:contract) do
    account.jrc_crm_contracts.create!(sales_order: order, owner: actor, contact: customer_person, business_unit: unit,
                                      content_override: 'TESTE SINTÉTICO — Minuta API de assinantes.')
  end
  let(:operation) do
    account.jrc_crm_backoffice_requests.create!(sales_order: order, contract: contract, owner: actor, requested_by: actor,
                                                contact: customer_person, business_unit: unit,
                                                title: 'TESTE SINTÉTICO — Assinantes API', stage: 'contract')
  end
  let(:headers) { actor.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/backoffice_requests/#{operation.id}/contract_signers" }
  let(:input) do
    { idempotency_key: SecureRandom.uuid, expected_revision: 0, expected_source_digest: JrcBackoffice::ContractSnapshot.digest(contract),
      customer_mode: 'single', issuer_mode: 'single', change_reason: 'TESTE SINTÉTICO — Conferir pessoas.',
      signers: [{ contact_id: customer_person.id, party: 'customer' }, { contact_id: issuer_person.id, party: 'issuer' }] }
  end

  before do
    account.enable_features!('jrc_crm', 'jrc_customer_master')
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: issuer, business_unit: unit,
                                                structure_managed: true, active: true)
    writer = JrcCustomers::SigningIdentityWriter.new(account: account, actor: actor)
    writer.save!(contact_id: customer_person.id, personal_tax_identifier: '11144477735', expected_revision: 0)
    writer.save!(contact_id: issuer_person.id, personal_tax_identifier: '52998224725', expected_revision: 0)
  end

  it 'derives the contract parties and returns only masked canonical contact identity' do
    other = create(:contact, account: account, company_id: issuer.id)
    get "#{url}/contacts", headers: headers, params: { party: 'customer', company_id: issuer.id, unit_id: 999 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('company', 'id')).to eq(customer.id)
    expect(response.parsed_body.fetch('data').pluck('id')).to eq([customer_person.id])
    expect(response.body).not_to include('11144477735', '52998224725', 'lookup_digest')
    expect(response.parsed_body.fetch('data').first).to include('selectable' => true, 'signing_authority_verified' => false)
    expect(response.parsed_body.fetch('data').pluck('id')).not_to include(other.id)
    expect(response.headers['Cache-Control']).to eq('no-store')
  end

  it 'paginates and searches the server-side party list without leaking another company' do
    12.times { |index| create(:contact, account: account, company_id: customer.id, name: "AAA TESTE #{index}") }
    get "#{url}/contacts", headers: headers, params: { party: 'customer', page: 1 }
    expect(response.parsed_body.fetch('data').length).to eq(10)
    get "#{url}/contacts", headers: headers, params: { party: 'customer', q: customer_person.email, page: 100 }
    expect(response.parsed_body.fetch('data').pluck('id')).to eq([customer_person.id])
    expect(response.parsed_body.fetch('meta')).to include('page' => 1, 'total' => 1)
    get "#{url}/contacts", headers: headers, params: { party: 'customer', q: '%_' }
    expect(response.parsed_body.fetch('data')).to be_empty
  end

  it 'creates and reloads the immutable proposal without accepting caller scope or granting powers' do
    post url, headers: headers, params: { signer_roster: input.merge(account_id: 999, created_by_id: 999, unit_id: 999) }, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch('id')
    get url, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('current', 'id')).to eq(id)
    expect(response.parsed_body).to include('writable' => true, 'signing_authority_verified' => false)
    expect(response.body).not_to include('11144477735', '52998224725', 'source_snapshot')
    expect(JrcBackoffice::SignerRoster.find(id)).to have_attributes(account_id: account.id, created_by_id: actor.id)
    expect(response.headers['Cache-Control']).to eq('no-store')
  end

  it 'returns conflict on a stale revision instead of silently replacing the selected people' do
    post url, headers: headers, params: { signer_roster: input }, as: :json
    expect(response).to have_http_status(:created)
    post url, headers: headers, params: { signer_roster: input.merge(idempotency_key: SecureRandom.uuid) }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('code')).to eq('CONTRACT_SIGNERS_CHANGED')
    expect(JrcBackoffice::SignerRoster.where(backoffice_request: operation).count).to eq(1)
  end

  it 'keeps history readable but blocks editing and contact selection after directory permission is withdrawn' do
    post url, headers: headers, params: { signer_roster: input }, as: :json
    expect(response).to have_http_status(:created)
    role = create(:custom_role, account: account, permissions: ['jrc_crm'])
    AccountUser.find_by!(account: account, user: actor).update!(role: :agent, custom_role: role)
    get url, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('writable')).to be(false)
    expect(response.body).not_to include('11144477735', '52998224725')
    get "#{url}/contacts", headers: headers, params: { party: 'customer' }
    expect(response).to have_http_status(:unauthorized)
    post url, headers: headers, params: { signer_roster: input.merge(idempotency_key: SecureRandom.uuid) }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.headers['Cache-Control']).to eq('no-store')
  end

  it 'denies foreign accounts, unassigned agents and records outside organizational coverage' do
    agent = create(:user, account: account, role: :agent)
    get url, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    foreign = create(:account)
    get url.sub("accounts/#{account.id}/", "accounts/#{foreign.id}/"), headers: headers
    expect(response).to have_http_status(:unauthorized)
    account.jrc_crm_user_business_units.structure_managed.where(user_id: actor.id).destroy_all
    get url, headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.headers['Cache-Control']).to eq('no-store')
  end
end
