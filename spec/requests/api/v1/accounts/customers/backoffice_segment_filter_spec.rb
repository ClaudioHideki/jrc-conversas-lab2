require 'rails_helper'

RSpec.describe 'Published customer segments in Backoffice reads', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:root) { "/api/v1/accounts/#{account.id}/crm/backoffice_requests" }
  let(:taxonomy) { JrcCustomers::Taxonomy.create!(account: account, name: 'Operations customers', kind: 'segment', modules: ['backoffice']) }
  let(:company) { account.master_companies.create!(name: 'Selected customer', segment: taxonomy.name) }
  let(:contact) { create(:contact, account: account, company_id: company.id) }
  let(:other_contact) { create(:contact, account: account) }
  let(:order) { account.jrc_crm_sales_orders.create!(owner: actor, contact: contact, status: 'approved') }
  let(:other_order) { account.jrc_crm_sales_orders.create!(owner: actor, contact: other_contact, status: 'approved') }
  let!(:selected) do
    account.jrc_crm_backoffice_requests.create!(owner: actor, requested_by: actor, contact: contact, sales_order: order,
                                                request_kind: 'change', title: 'Selected request')
  end
  let!(:second) do
    account.jrc_crm_backoffice_requests.create!(owner: actor, requested_by: actor, contact: contact, sales_order: order,
                                                request_kind: 'change', title: 'Second request')
  end
  let!(:unmatched) do
    account.jrc_crm_backoffice_requests.create!(owner: actor, requested_by: actor, contact: other_contact, sales_order: other_order,
                                                request_kind: 'change', title: 'Unmatched request')
  end

  before { account.enable_features!('jrc_crm', 'jrc_customer_master') }

  it 'keeps native responses without a segment and narrows the list without modifying records' do
    get root, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.pluck('id')).to contain_exactly(selected.id, second.id, unmatched.id)
    original = [selected, second, unmatched].map(&:attributes)
    get root, headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.pluck('id')).to contain_exactly(selected.id, second.id)
    expect([selected, second, unmatched].map { |row| row.reload.attributes }).to eq(original)
  end

  it 'uses the same selected scope for workspace totals, summary and the overview dashboard' do
    get "#{root}/summary", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('total')).to eq(2)
    get "#{root}/workspace", headers: headers, params: { customer_segment_id: taxonomy.id, view: 'overview', per_page: 1 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('data').pluck('id')).to eq([second.id])
    expect(response.parsed_body.fetch('meta')).to include('total' => 2, 'page' => 1, 'pages' => 2)
    expect(response.parsed_body.fetch('summary').fetch('total')).to eq(2)
    expect(response.parsed_body.fetch('dashboard').fetch('mine').pluck('id')).to contain_exactly(selected.id, second.id)
  end

  it 'paginates inside the selected scope without counting an unmatched request' do
    get "#{root}/workspace", headers: headers, params: { customer_segment_id: taxonomy.id, page: 2, per_page: 1 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('data').pluck('id')).to eq([selected.id])
    expect(response.parsed_body.fetch('meta')).to include('total' => 2, 'page' => 2, 'pages' => 2)
  end

  it 'keeps mine and owner scopes and does not trust forged user or unit selectors' do
    colleague = create(:user, account: account, role: :agent)
    second.update!(owner: colleague)
    account.account_users.find_by!(user: actor).update!(role: :agent)
    get "#{root}/workspace", headers: headers,
                             params: { customer_segment_id: taxonomy.id, view: 'mine', user_id: colleague.id, unit_id: 0 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('data').pluck('id')).to eq([selected.id])
    expect(response.parsed_body.fetch('summary').fetch('total')).to eq(1)
  end

  it 'intersects organizational coverage even when the same customer is included in the segment' do
    issuer = account.master_companies.create!(name: 'Allowed operator', relationship_type: 'internal')
    other_issuer = account.master_companies.create!(name: 'Other operator', relationship_type: 'internal')
    unit = account.jrc_crm_business_units.create!(name: 'Allowed unit', code: 'BKO-SEG-A', company_id: issuer.id)
    other_unit = account.jrc_crm_business_units.create!(name: 'Other unit', code: 'BKO-SEG-B', company_id: other_issuer.id)
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, business_unit: unit, scope: 'BUSINESS_UNIT', structure_managed: true)
    order.update!(business_unit: unit)
    selected.update!(business_unit: unit)
    second.update!(business_unit: other_unit)
    get "#{root}/workspace", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('data').pluck('id')).to eq([selected.id])
  end

  it 'does not confuse CRM publication with Backoffice publication and rechecks active status' do
    taxonomy.update!(modules: ['crm'])
    get "#{root}/workspace", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:not_found)
    taxonomy.update!(modules: ['backoffice'], active: false)
    get "#{root}/summary", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:not_found)
  end

  it 'rejects foreign taxonomy identifiers even for an actor with memberships in both accounts' do
    foreign = create(:account)
    create(:account_user, account: foreign, user: actor, role: :administrator)
    segment = JrcCustomers::Taxonomy.create!(account: foreign, name: 'Foreign operations', kind: 'segment', modules: ['backoffice'])
    get root, headers: headers, params: { customer_segment_id: segment.id, account_id: foreign.id }
    expect(response).to have_http_status(:not_found)
  end

  it 'retains explicit contact exclusions without falling back to a matching company' do
    JrcCustomers::SegmentOverride.create!(account: account, taxonomy: taxonomy, contact: contact, mode: 'exclude')
    get "#{root}/workspace", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('data')).to eq([])
    expect(response.parsed_body.fetch('summary').fetch('total')).to eq(0)
  end

  it 'requires directory access for the extra filter and leaves unfiltered Backoffice usable' do
    role = create(:custom_role, account: account, permissions: ['jrc_crm'])
    account.account_users.find_by!(user: actor).update!(role: :agent, custom_role: role)
    get root, headers: headers
    expect(response).to have_http_status(:ok)
    get root, headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'keeps the list selector out of native show authorization' do
    get "#{root}/#{unmatched.id}", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('id')).to eq(unmatched.id)
  end
end
