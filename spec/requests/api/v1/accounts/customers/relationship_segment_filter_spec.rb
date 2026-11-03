require 'rails_helper'

RSpec.describe 'Published customer segments in native Relationship reads', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :agent) }
  let(:colleague) { create(:user, account: account, role: :agent) }
  let(:headers) { actor.create_new_auth_token }
  let(:root) { "/api/v1/accounts/#{account.id}/relationship" }
  let(:taxonomy) { JrcCustomers::Taxonomy.create!(account: account, name: 'Relationship customers', kind: 'segment', modules: ['relationship']) }
  let(:company) { account.master_companies.create!(name: 'Selected customer', segment: taxonomy.name) }
  let(:contact) { create(:contact, account: account, company_id: company.id) }
  let(:selected) { JrcRelationship::Assignment.create!(account: account, company: company, owner: actor) }
  let(:contact_assignment) { JrcRelationship::Assignment.create!(account: account, contact: contact, owner: actor) }
  let(:unmatched) { JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account), owner: actor) }
  let(:hidden) do
    JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account, company_id: company.id), owner: colleague)
  end

  before do
    account.enable_features!('jrc_customer_master', 'jrc_relationship')
    selected
    contact_assignment
    unmatched
    hidden
  end

  it 'intersects the native portfolio and never exposes another owners matching customer' do
    get "#{root}/portfolio", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').pluck('id')).to contain_exactly(selected.id, contact_assignment.id, unmatched.id)
    original = [selected, contact_assignment, unmatched, hidden].map(&:attributes)
    get "#{root}/portfolio", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').pluck('id')).to contain_exactly(selected.id, contact_assignment.id)
    expect([selected, contact_assignment, unmatched, hidden].map { |row| row.reload.attributes }).to eq(original)
  end

  it 'uses the same cohort for dashboard and paginated portfolio' do
    get "#{root}/dashboard", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('customers')).to eq(2)
    get "#{root}/portfolio", headers: headers, params: { customer_segment_id: taxonomy.id, page: 2, per_page: 1 }
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([selected.id])
    expect(response.parsed_body.fetch('meta')).to include('total' => 2, 'page' => 2)
  end

  it 'filters action lists through both native record visibility and the selected portfolio' do
    action = JrcRelationship::Action.create!(account: account, assignment: selected, owner: actor,
                                             kind: 'manual', reason: 'Selected action', source_key: 'segment-selected')
    JrcRelationship::Action.create!(account: account, assignment: unmatched, owner: actor,
                                    kind: 'manual', reason: 'Other action', source_key: 'segment-unmatched')
    get "#{root}/records/actions", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([action.id])
  end

  it 'keeps contact exclusions explicit while retaining the separately matching company assignment' do
    JrcCustomers::SegmentOverride.create!(account: account, taxonomy: taxonomy, contact: contact, mode: 'exclude')
    get "#{root}/portfolio", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([selected.id])
  end

  it 'combines the legacy assignment classification with the new independently published segment' do
    classification = JrcCustomers::Taxonomy.create!(account: account, name: 'Legacy class', kind: 'segment')
    selected.update!(settings: { segment_id: classification.id })
    get "#{root}/portfolio", headers: headers, params: { customer_segment_id: taxonomy.id, segment_id: classification.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([selected.id])
  end

  it 'rechecks publication, active state and account isolation rather than trusting identifiers' do
    foreign = create(:account)
    create(:account_user, account: foreign, user: actor, role: :administrator)
    segment = JrcCustomers::Taxonomy.create!(account: foreign, name: 'Foreign relationship', kind: 'segment', modules: ['relationship'])
    get "#{root}/portfolio", headers: headers, params: { customer_segment_id: segment.id, user_id: colleague.id }
    expect(response).to have_http_status(:not_found)
    taxonomy.update!(modules: ['crm'])
    get "#{root}/dashboard", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:not_found)
    taxonomy.update!(modules: ['relationship'], active: false)
    get "#{root}/portfolio", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:not_found)
  end

  it 'rechecks module and Directory permissions on every call' do
    role = create(:custom_role, account: account, permissions: ['jrc_relationship_view'])
    account.account_users.find_by!(user: actor).update!(custom_role: role)
    get "#{root}/portfolio", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:forbidden)
    role.update!(permissions: ['contact_manage'])
    get "#{root}/portfolio", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:forbidden)
  end

  it 'preserves native detail authorization independently from a list filter' do
    get "#{root}/portfolio/#{unmatched.id}", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('id')).to eq(unmatched.id)
    get "#{root}/portfolio/#{hidden.id}", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:not_found)
  end

  it 'retains native operator and unit coverage even for two assignments in the same segment' do
    issuer = account.master_companies.create!(name: 'Allowed operator', relationship_type: 'internal')
    other_issuer = account.master_companies.create!(name: 'Other operator', relationship_type: 'internal')
    unit = account.jrc_crm_business_units.create!(name: 'Allowed unit', code: 'REL-SEG-A', company_id: issuer.id)
    other_unit = account.jrc_crm_business_units.create!(name: 'Other unit', code: 'REL-SEG-B', company_id: other_issuer.id)
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, business_unit: unit, scope: 'BUSINESS_UNIT', structure_managed: true)
    selected.update!(business_unit: unit)
    contact_assignment.update!(business_unit: other_unit)
    get "#{root}/portfolio", headers: headers, params: { customer_segment_id: taxonomy.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([selected.id])
  end
end
