require 'rails_helper'

RSpec.describe 'Native analyst withdrawal readiness', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:analyst) { create(:user, account: account, role: :agent) }
  let(:headers) { actor.create_new_auth_token }
  let(:allocation) { JrcRelationship::Assignment.create!(account: account, owner: analyst, contact: create(:contact, account: account)) }
  let(:url) { "/api/v1/accounts/#{account.id}/relationship/team/#{analyst.id}/withdrawal_readiness" }

  before { account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm') }

  it 'uses real current pending ownership independently of root allocation ownership and makes no membership change' do
    action = JrcRelationship::Action.create!(account: account, assignment: allocation, owner: analyst, kind: 'task',
                                             source_key: SecureRandom.uuid, reason: 'Synthetic remaining task')
    allocation.update!(owner: actor)
    before = [AccountUser.where(account: account).count, TeamMember.count, action.owner_id]
    get url, headers: headers
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body).to include('state' => 'pending_responsibilities', 'final_removal_available' => false)
    expect(response.parsed_body.fetch('counts')).to include('allocations' => 0, 'actions' => 1)
    expect([AccountUser.where(account: account).count, TeamMember.count, action.reload.owner_id]).to eq(before)
    expect(response.body).not_to include('Synthetic remaining task', 'source_snapshot')
    expect(response.parsed_body.fetch('snapshot_digest')).to match(/\A[a-f0-9]{64}\z/)
  end

  it 'retains historical inactive allocations and reports only readiness for a separate final review, never a completed removal' do
    allocation.update!(status: 'inactive')
    get url, headers: headers
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body).to include('state' => 'ready_for_final_review', 'final_removal_available' => false)
    expect(allocation.reload.owner_id).to eq(analyst.id)
    expect(account.account_users.where(user: analyst)).to exist
  end

  it 'denies another account without returning workload counts or a readiness digest' do
    outsider = create(:user, account: create(:account), role: :administrator)
    get url, headers: outsider.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).not_to have_key('counts')
    expect(response.parsed_body).not_to have_key('snapshot_digest')
  end

  it 'includes a pending CRM commitment referenced by a plan even after both root and plan owners changed' do
    lead = account.jrc_crm_leads.create!(owner: analyst, contact: allocation.contact, name: 'Synthetic commitment lead')
    activity = account.jrc_crm_activities.create!(user: analyst, lead: lead, contact: allocation.contact,
                                                  title: 'Synthetic referenced commitment', activity_type: 'task')
    allocation.update!(owner: actor)
    JrcRelationship::SuccessPlan.create!(account: account, assignment: allocation, owner: actor, title: 'Synthetic reassigned plan',
                                         goals: [{ 'metric' => 'Synthetic delivery', 'activity_id' => activity.id }])
    get url, headers: headers
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('counts')).to include('allocations' => 0, 'plans' => 0, 'activities' => 1)
    expect(response.parsed_body.fetch('state')).to eq('pending_responsibilities')
  end

  it 'does not turn hidden unit allocations into zero workload' do
    company = account.master_companies.create!(name: 'Synthetic readiness issuer', relationship_type: 'internal', tax_id: '11444777000161')
    units = Array.new(2) do |index|
      account.jrc_crm_business_units.create!(name: "Synthetic #{index}", code: SecureRandom.hex(6), company_id: company.id)
    end
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: company,
                                                business_unit: units.first, active: true, structure_managed: true)
    allocation.update!(business_unit: units.last)
    get url, headers: headers
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).not_to have_key('counts')
  end
end
