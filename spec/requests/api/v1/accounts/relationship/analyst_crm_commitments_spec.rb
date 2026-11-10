require 'rails_helper'

RSpec.describe 'Scoped analyst CRM commitment origins', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:analyst) { create(:user, account: account, role: :agent) }
  let(:headers) { actor.create_new_auth_token }
  let(:contact) { create(:contact, account: account) }
  let(:lead) { account.jrc_crm_leads.create!(owner: analyst, contact: contact, name: 'Synthetic commitment origin') }
  let(:allocation) { JrcRelationship::Assignment.create!(account: account, owner: actor, contact: contact) }
  let(:activity) do
    account.jrc_crm_activities.create!(user: analyst, contact: contact, lead: lead, title: 'Synthetic linked commitment', activity_type: 'meeting',
                                       description: 'Private commitment notes', metadata: { relationship_assignment_id: allocation.id })
  end
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/team/#{analyst.id}/native_responsibilities" }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'paginates current linked CRM commitments and opens the exact native editor without changing work or account membership' do
    rows = [activity] + Array.new(10) do |index|
      account.jrc_crm_activities.create!(user: analyst, contact: contact, lead: lead,
                                         title: "Synthetic remaining task #{index}", activity_type: 'task',
                                         metadata: { relationship_assignment_id: allocation.id })
    end
    account.jrc_crm_activities.create!(user: analyst, contact: contact, lead: lead, title: 'Unrelated CRM work', activity_type: 'task')
    account.jrc_crm_activities.create!(user: analyst, contact: contact, lead: lead, title: 'Historical commitment',
                                       activity_type: 'task', status: 'completed',
                                       metadata: { relationship_assignment_id: allocation.id })
    before = [rows.map(&:attributes), account.account_users.order(:id).map(&:attributes)]
    get url, headers: headers, params: { kind: 'activities' }
    expect(response).to have_http_status(:ok), response.body
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.parsed_body.fetch('meta')).to include('total' => 11, 'page' => 1, 'per_page' => 10)
    get url, headers: headers, params: { kind: 'activities', page: 2 }
    route = { 'name' => 'crm_activities', 'params' => { 'accountId' => account.id }, 'query' => { 'activityId' => rows.last.id } }
    expect(response.parsed_body.fetch('payload')).to contain_exactly(include('id' => rows.last.id, 'status' => 'scheduled', 'source_route' => route))
    expect(response.body).not_to include('Private commitment notes', 'Unrelated CRM work', 'Historical commitment', 'metadata', 'description')
    expect([rows.map { |row| row.reload.attributes }, account.account_users.order(:id).map(&:attributes)]).to eq(before)
  end

  it 'retains a plan commitment after root and plan ownership changed and deduplicates shared goal and milestone references' do
    activity.update!(metadata: {})
    JrcRelationship::SuccessPlan.create!(account: account, assignment: allocation, owner: actor, title: 'Reassigned plan',
                                         goals: [{ 'metric' => 'Delivery', 'activity_id' => activity.id }],
                                         metadata: { milestones: [{ title: 'Shared native milestone', activity_id: activity.id }] })
    get url, headers: headers, params: { kind: 'activities' }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([activity.id])
    get "/api/v1/accounts/#{account.id}/relationship/team/#{analyst.id}/withdrawal_readiness", headers: headers
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('counts')).to include('allocations' => 0, 'plans' => 0, 'activities' => 1)
    expect(response.parsed_body.fetch('final_removal_available')).to be(false)
  end

  it 'keeps a native action reference after metadata is absent and excludes it after the native commitment is completed' do
    activity.update!(metadata: {})
    JrcRelationship::Action.create!(account: account, assignment: allocation, owner: actor, kind: 'meeting',
                                    activity: activity, reason: 'Synthetic referenced meeting', source_key: SecureRandom.uuid)
    get url, headers: headers, params: { kind: 'activities' }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([activity.id])
    activity.update!(status: 'completed', completed_at: Time.current)
    get url, headers: headers, params: { kind: 'activities' }
    expect(response.parsed_body.fetch('meta').fetch('total')).to eq(0)
  end

  it 'denies CRM module revocation before disclosing titles or counts' do
    activity
    account.disable_features!('jrc_crm')
    get url, headers: headers, params: { kind: 'activities', user_id: actor.id }
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include(activity.title, 'total', 'payload')
  end

  it 'does not grant another analyst native CRM ownership through Relationship team permission' do
    activity
    role = create(:custom_role, account: account, permissions: %w[contact_manage jrc_relationship_view jrc_relationship_team])
    account.account_users.find_by!(user: actor).update!(role: :agent, custom_role: role)
    get url, headers: headers, params: { kind: 'activities', account_id: account.id, user_id: analyst.id }
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include(activity.title, 'total', 'payload')
  end

  it 'denies hidden corporate-unit commitments instead of showing a misleading partial workload' do
    company = account.master_companies.create!(name: 'Synthetic native issuer', relationship_type: 'internal', tax_id: '11444777000161')
    units = Array.new(2) do |index|
      account.jrc_crm_business_units.create!(name: "Synthetic commitment unit #{index}", code: SecureRandom.hex(6), company_id: company.id)
    end
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: company,
                                                business_unit: units.first, active: true, structure_managed: true)
    activity.update!(business_unit: units.last)
    get url, headers: headers, params: { kind: 'activities', unit_id: units.last.id }
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include(activity.title, 'total', 'payload')
  end

  it 'rejects foreign analysts and foreign plan-origin IDs without disclosing native commitment data' do
    foreign_account = create(:account)
    foreign_actor = create(:user, account: foreign_account, role: :administrator)
    foreign_lead = foreign_account.jrc_crm_leads.create!(owner: foreign_actor, name: 'Foreign synthetic origin')
    foreign_activity = foreign_account.jrc_crm_activities.create!(user: foreign_actor, lead: foreign_lead,
                                                                  title: 'Foreign private commitment', activity_type: 'task')
    get "/api/v1/accounts/#{account.id}/relationship/team/#{foreign_actor.id}/native_responsibilities", headers: headers,
                                                                                                        params: { kind: 'activities' }
    expect(response).to have_http_status(:not_found)
    JrcRelationship::SuccessPlan.create!(account: account, assignment: allocation, owner: actor, title: 'Requires native correction',
                                         goals: [{ 'metric' => 'Delivery', 'activity_id' => foreign_activity.id }])
    get url, headers: headers, params: { kind: 'activities' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).not_to include('Foreign private commitment', 'payload', 'total')
  end
end
