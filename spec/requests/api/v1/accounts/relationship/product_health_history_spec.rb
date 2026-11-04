require 'rails_helper'

RSpec.describe 'Authorized native product health history', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: user) }
  let(:context) { JrcRelationship::Context.new(member) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account), owner: user) }
  let(:product) { create(:jrc_crm_product, account: account) }
  let(:headers) { user.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/portfolio/#{assignment.id}/product_health_history" }
  let(:health) do
    { score: 50, band: 'risk', factors: [{ factor: 'adoption', normalized: 50, contribution: 50, evidence: 'Synthetic authorized product goal' }],
      config_scope_key: "product:#{product.id}", config_version: 2 }
  end
  let(:attributes) do
    { account: account, assignment: assignment, viewer: user, access_signature: context.access_signature,
      score: 90, band: 'healthy', factors: [], config_scope_key: 'account', config_version: 1,
      signals: { '_source_ids' => {}, 'product_health' => { product.id.to_s => health, '9999999' => { score: 9, private_other: 'OTHER-PRODUCT' } } },
      calculated_at: Time.current, fingerprint: SecureRandom.hex(16) }
  end

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'returns preserved product measurements and evidence rather than substituting the customer score or another product' do
    old_signals = { '_source_ids' => {}, 'product_health' => { product.id.to_s => health.merge(score: 30) } }
    older = JrcRelationship::HealthSnapshot.create!(**attributes, calculated_at: 1.day.ago, fingerprint: SecureRandom.hex(16), signals: old_signals)
    latest = JrcRelationship::HealthSnapshot.create!(**attributes)
    before = JrcRelationship::HealthSnapshot.where(account: account).count
    get url, headers: headers, params: { product_id: product.id }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body).to include('product_id' => product.id, 'meta' => { 'page' => 1, 'per_page' => 10, 'total' => 2 })
    expect(response.parsed_body['payload']).to include(a_hash_including('id' => latest.id,
                                                                        'health' => health.deep_stringify_keys,
                                                                        'change' => a_hash_including('delta' => 20,
                                                                                                     'configuration_changed' => false)))
    expect(response.body).not_to include('OTHER-PRODUCT', 'private_other', 'access_signature', '_source_ids', 'fingerprint')
    expect([JrcRelationship::HealthSnapshot.where(account: account).count, older.reload.score, latest.reload.score]).to eq([before, 90, 90])
  end

  it 'paginates actual rows and compares with the authorized next observation across a page boundary' do
    rows = Array.new(3) do |index|
      signals = { '_source_ids' => {}, 'product_health' => { product.id.to_s => health.merge(score: 50 - (index * 5)) } }
      JrcRelationship::HealthSnapshot.create!(**attributes, fingerprint: SecureRandom.hex(16), calculated_at: index.hours.ago,
                                                            signals: signals)
    end
    get url, headers: headers, params: { product_id: product.id, page: 1, per_page: 1 }
    expect(response.parsed_body['payload']).to match([a_hash_including('id' => rows[0].id, 'change' => a_hash_including('delta' => 5))])
    get url, headers: headers, params: { product_id: product.id, page: 2, per_page: 1 }
    expect(response.parsed_body['payload'].pluck('id')).to eq([rows[1].id])
    expect(response.parsed_body['meta']).to eq('page' => 2, 'per_page' => 1, 'total' => 3)
    expect(JrcRelationship::HealthSnapshot.where(account: account).count).to eq(3)
  end

  it 'keeps unavailable scores unavailable and flags a product model/version change' do
    old_signals = { '_source_ids' => {}, 'product_health' => { product.id.to_s => health.merge(config_version: 1) } }
    JrcRelationship::HealthSnapshot.create!(**attributes, calculated_at: 1.day.ago, fingerprint: SecureRandom.hex(16), signals: old_signals)
    JrcRelationship::HealthSnapshot.create!(**attributes)
    get url, headers: headers, params: { product_id: product.id }
    expect(response.parsed_body['payload'].first.dig('change', 'configuration_changed')).to be(true)
    unavailable = { '_source_ids' => {}, 'product_health' => { product.id.to_s => health.merge(score: nil, band: 'unavailable') } }
    JrcRelationship::HealthSnapshot.create!(**attributes, fingerprint: SecureRandom.hex(16), calculated_at: 1.minute.from_now, signals: unavailable)
    get url, headers: headers, params: { product_id: product.id }
    expect(response.parsed_body['payload'].first).to include('health' => a_hash_including('score' => nil, 'band' => 'unavailable'), 'change' => nil)
  end

  it 'does not borrow another viewer, access signature or private portfolio history' do
    other = create(:user, account: account)
    other_assignment = JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account), owner: other)
    [{ viewer: other }, { access_signature: 'old-permissions' }, { assignment: other_assignment }].each do |changes|
      JrcRelationship::HealthSnapshot.create!(**attributes, **changes, fingerprint: SecureRandom.hex(16))
    end
    get url, headers: headers, params: { product_id: product.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('payload' => [], 'meta' => a_hash_including('total' => 0))
    get "/api/v1/accounts/#{account.id}/relationship/portfolio/#{other_assignment.id}/product_health_history", headers: headers,
                                                                                                               params: { product_id: product.id }
    expect(response).to have_http_status(:not_found)
  end

  it 'filters native evidence after a source becomes private or belongs to another account' do
    foreign = create(:account)
    owner = create(:user, account: foreign)
    order = foreign.jrc_crm_sales_orders.create!(owner: owner, status: 'approved')
    contract = foreign.jrc_crm_contracts.create!(sales_order: order, owner: owner)
    JrcRelationship::HealthSnapshot.create!(**attributes,
                                             signals: attributes[:signals].merge('_source_ids' => { 'contracts' => [contract.id] }))
    get url, headers: headers, params: { product_id: product.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('payload' => [], 'meta' => a_hash_including('total' => 0))
  end

  it 'denies another account and ignores forged identity or owner parameters' do
    JrcRelationship::HealthSnapshot.create!(**attributes)
    outsider = create(:user, account: create(:account))
    get url, headers: outsider.create_new_auth_token, params: { product_id: product.id, user_id: user.id, account_id: account.id }
    expect(response).to have_http_status(:forbidden)
    assignment.update!(owner: create(:user, account: account))
    get url, headers: headers, params: { product_id: product.id, owner_id: user.id }
    expect(response).to have_http_status(:not_found)
  end

  it 'reauthorizes the portfolio after projection and never returns stale evidence after ownership revocation' do
    JrcRelationship::HealthSnapshot.create!(**attributes)
    other = create(:user, account: account)
    allow(JrcRelationship::HealthChange).to receive(:call).and_wrap_original do |original, **values|
      result = original.call(**values)
      assignment.update!(owner: other)
      result
    end
    get url, headers: headers, params: { product_id: product.id }
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('Synthetic authorized product goal')
  end

  it 'requires native relationship access and current permission signatures' do
    JrcRelationship::HealthSnapshot.create!(**attributes)
    member.update!(custom_role: create(:custom_role, account: account, permissions: ['contact_manage']))
    get url, headers: headers, params: { product_id: product.id }
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include('Synthetic authorized product goal')
  end

  it 'keeps native issuer/unit boundaries after an organizational grant is revoked' do
    company = account.master_companies.create!(name: 'Synthetic operating issuer', relationship_type: 'internal')
    unit = account.jrc_crm_business_units.create!(name: 'Synthetic portfolio unit', code: 'product-history-unit', company_id: company.id)
    grant = JrcCrm::UserBusinessUnit.create!(account: account, user: user, company: company, business_unit: unit,
                                             scope: 'BUSINESS_UNIT', structure_managed: true)
    assignment.update!(business_unit: unit)
    JrcRelationship::HealthSnapshot.create!(**attributes)
    get url, headers: headers, params: { product_id: product.id }
    expect(response).to have_http_status(:ok), response.body
    grant.update!(active: false)
    get url, headers: headers, params: { product_id: product.id, business_unit_id: unit.id }
    expect(response).to have_http_status(:not_found)
  end

  it 'bounds pages and requires an explicit valid product rather than silently returning all products' do
    [{ product_id: -1 }, { product_id: product.id, page: 0 }, { product_id: product.id, per_page: 51 }].each do |values|
      get url, headers: headers, params: values
      expect(response).to have_http_status(:unprocessable_entity)
    end
    get url, headers: headers, params: { product_id: product.id }
    expect(response.parsed_body).to include('payload' => [], 'meta' => a_hash_including('total' => 0))
  end
end
