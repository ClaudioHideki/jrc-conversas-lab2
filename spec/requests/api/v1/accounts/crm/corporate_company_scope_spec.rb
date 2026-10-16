require 'rails_helper'

RSpec.describe 'CRM corporate companies and issuer coverage', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/crm" }
  let(:contact) { create(:contact, account: account) }
  let(:company) { account.master_companies.create!(name: 'Operadora JRC', relationship_type: 'internal') }
  let(:other_company) { account.master_companies.create!(name: 'GoPure', relationship_type: 'internal') }
  let(:unit) { account.jrc_crm_business_units.create!(name: 'Telecom sintética', code: 'telecom', company_id: company.id) }
  let(:other_unit) { account.jrc_crm_business_units.create!(name: 'Comércio sintético', code: 'commerce', company_id: other_company.id) }

  before { account.enable_features!('jrc_crm', 'jrc_customer_master') }

  it 'registers the three initial companies in the native master, with pending fiscal data and selectable native units' do
    JrcCrm::UserBusinessUnit.create!(account: account, user: admin, scope: 'GROUP', structure_managed: true)
    [['Operadora JRC', 'Telecom'], ['GoPure', 'Comércio / Produtos'],
     ['Construtora JRC', 'Construção civil']].each_with_index do |(name, segment), index|
      post "#{base}/organization_structure/companies", params: { company: { name: name, segment: segment, active: true } }, headers: headers,
                                                       as: :json
      expect(response).to have_http_status(:created), response.body
      registered = account.master_companies.find_by!(name: name)
      expect(registered).to have_attributes(relationship_type: 'internal', tax_id: nil, segment: segment)
      expect(JrcCrm::CorporateProfile.read(registered)).to eq({})
      post "#{base}/organization_structure/business_units", params: { business_unit: {
        company_id: registered.id, name: "Unidade sintética #{index}", code: "synthetic-#{index}"
      } }, headers: headers, as: :json
      expect(response).to have_http_status(:created), response.body
    end
    get "#{base}/proposals/creation_options", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['business_units'].length).to eq(3)
    expect(response.parsed_body['unit_required']).to be(true)
  end

  it 'does not give an administrator automatic corporate document, unit or company access' do
    document = account.jrc_crm_proposals.create!(owner: admin, contact: contact, business_unit: other_unit, title: 'Restricted synthetic proposal')
    get "#{base}/proposals/#{document.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    get "#{base}/proposals/creation_options", headers: headers
    expect(response.parsed_body['business_units']).to eq([])
    get "/api/v1/accounts/#{account.id}/customers/companies/#{other_company.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(account.jrc_crm_user_business_units.structure_managed.count).to eq(0)
  end

  it 'allows only the explicit company coverage and rejects swapping IDs in API submissions' do
    JrcCrm::UserBusinessUnit.create!(account: account, user: admin, company: company, scope: 'COMPANY', structure_managed: true)
    allowed = account.jrc_crm_proposals.create!(owner: admin, contact: contact, business_unit: unit, title: 'Allowed synthetic proposal')
    blocked = account.jrc_crm_proposals.create!(owner: admin, contact: contact, business_unit: other_unit, title: 'Blocked synthetic proposal')
    get "#{base}/proposals", headers: headers
    expect(response.parsed_body.pluck('id')).to include(allowed.id)
    expect(response.parsed_body.pluck('id')).not_to include(blocked.id)
    post "#{base}/proposals", params: { business_unit_id: other_unit.id }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    patch "#{base}/organization_structure/companies/#{other_company.id}", params: { company: { name: 'Changed' } }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(other_company.reload.name).to eq('GoPure')
  end

  it 'bounds products and metrics even when the legacy optional enforcement flag is off' do
    JrcCrm::UserBusinessUnit.create!(account: account, user: admin, company: company, scope: 'COMPANY', structure_managed: true)
    allowed = account.jrc_crm_products.create!(name: 'Allowed product', business_unit_id: unit.id)
    blocked = account.jrc_crm_products.create!(name: 'Blocked product', business_unit_id: other_unit.id)
    get "#{base}/products", headers: headers
    expect(response.parsed_body.pluck('id')).to include(allowed.id)
    expect(response.parsed_body.pluck('id')).not_to include(blocked.id)
    patch "#{base}/products/#{allowed.id}", params: { product: { business_unit_id: other_unit.id } }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    patch "#{base}/products/#{allowed.id}", params: { product: { business_unit_id: nil } }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(allowed.reload.business_unit_id).to eq(unit.id)
  end

  it 'rejects a unit from another account in API and service calls' do
    alien = create(:account).jrc_crm_business_units.create!(name: 'Alien synthetic unit', code: 'alien')
    post "#{base}/proposals", params: { business_unit_id: alien.id }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect do
      JrcCrm::ProposalBuilderService.new(account: account, actor: admin, business_unit: alien).call
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'keeps issuer independent of recipient/customer and refuses a product from another issuer unit' do
    JrcCrm::UserBusinessUnit.create!(account: account, user: admin, scope: 'GROUP', structure_managed: true)
    customer = account.master_companies.create!(name: 'Synthetic customer')
    product = account.jrc_crm_products.create!(name: 'Other company product', business_unit_id: other_unit.id, unit_price_cents: 1000)
    expect do
      JrcCrm::ProposalBuilderService.new(account: account, actor: admin, company: customer, business_unit: unit,
                                         items: [{ product_id: product.id, unit_price_cents: 1000 }]).call
    end.to raise_error(ActiveRecord::RecordNotFound)
    proposal = JrcCrm::ProposalBuilderService.new(account: account, actor: admin, company: customer, business_unit: unit).call
    payload = JrcCrm::ProposalSerializer.new(proposal).as_json
    expect(payload[:issuer_company_id]).to eq(company.id)
    expect(proposal).to have_attributes(company_id: customer.id, issuer_company_name: 'Operadora JRC', issuer_tax_id: nil)
  end

  it 'requires same-account native authorities and an explicit authorization reference' do
    JrcCrm::UserBusinessUnit.create!(account: account, user: admin, scope: 'GROUP', structure_managed: true)
    foreign = create(:account_user)
    patch "#{base}/organization_structure/companies/#{company.id}", params: { company: { profile: {
      commercial_gratuity_principal_id: foreign.id, authorization_reference: 'Synthetic authorized configuration'
    } } }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    patch "#{base}/organization_structure/companies/#{company.id}", params: { company: { profile: {
      commercial_gratuity_principal_id: account.account_users.find_by!(user: admin).id
    } } }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcCrm::CorporateProfile.read(company.reload)).to eq({})
  end

  it 'does not let an administrator with company coverage grant corporate coverage to themselves' do
    unit
    JrcCrm::UserBusinessUnit.create!(account: account, user: admin, company: company, scope: 'COMPANY', structure_managed: true)
    post "#{base}/organization_structure/user_scopes", params: { user_scope: { user_id: admin.id, scope: 'GROUP', active: true } },
                                                       headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(account.jrc_crm_user_business_units.where(user: admin, scope: 'GROUP')).to be_empty
  end

  it 'applies company coverage to address and contact-filter endpoints' do
    unit
    JrcCrm::UserBusinessUnit.create!(account: account, user: admin, company: company, scope: 'COMPANY', structure_managed: true)
    post "/api/v1/accounts/#{account.id}/customers/companies/#{other_company.id}/addresses",
         params: { address: { street: 'Synthetic forbidden address' } }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(other_company.addresses).to be_empty
    get "/api/v1/accounts/#{account.id}/customers/contacts", params: { company_id: other_company.id }, headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'persists a typed free-installation declaration through the native proposal API without sending or activating' do
    JrcCrm::UserBusinessUnit.create!(account: account, user: admin, scope: 'GROUP', structure_managed: true)
    product = account.jrc_crm_products.create!(name: 'Synthetic monthly product', business_unit_id: unit.id,
                                               unit_price_cents: 100_000, minimum_price_cents: 90_000,
                                               setup_fee_cents: 20_000, billing_model: 'monthly')
    post "#{base}/proposals", params: { business_unit_id: unit.id, contact_id: contact.id, items: [{
      product_id: product.id, quantity: 1, unit_price_cents: 100_000,
      commercial_gratuity: { type: 'installation', reason: 'Synthetic commercial installation waiver' }
    }] }, headers: headers, as: :json
    expect(response).to have_http_status(:created), response.body
    document = account.jrc_crm_proposals.find(response.parsed_body['id'])
    expect(document.proposal_items.first).to have_attributes(setup_fee_cents: 0,
                                                             commercial_gratuity: {
                                                               'type' => 'installation', 'reason' => 'Synthetic commercial installation waiver'
                                                             })
    expect(JrcApprovals::CommercialGratuity.new(resource: document).call).to include(
      has_commercial_gratuity: true, gratuity_total_cents: 20_000
    )
    expect(account.reload.feature_enabled?('jrc_approvals')).to be(false)
    expect(Message.where(account: account)).to be_empty
  end
end
