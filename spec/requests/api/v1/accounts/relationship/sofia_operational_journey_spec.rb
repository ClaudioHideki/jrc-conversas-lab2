require 'rails_helper'

# Native authenticated HTTP + PostgreSQL acceptance. This is not browser/CSS
# homologation and does not use a real customer, channel or provider.
RSpec.describe 'SYNTHETIC Sofia operational journey', type: :request do
  let(:account) { create(:account) }
  let(:sofia) { create(:user, account: account, role: :agent, name: 'SYNTHETIC Sofia') }
  let(:colleague) { create(:user, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: sofia) }
  let(:headers) { sofia.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/relationship" }
  let(:role) do
    create(:custom_role, account: account, name: 'SYNTHETIC operational analyst',
                         permissions: %w[contact_manage jrc_crm jrc_relationship_view jrc_relationship_manage])
  end
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC Sofia customer') }
  let(:contact) { create(:contact, account: account, company_id: company.id) }
  let(:pipeline) { create(:jrc_crm_pipeline, account: account) }
  let(:stage) { create(:jrc_crm_stage, account: account, pipeline: pipeline) }
  let(:deal) { create(:jrc_crm_deal, account: account, pipeline: pipeline, stage: stage, owner: sofia, contact: contact, company: company) }
  let(:assignment) { JrcRelationship::Assignment.create!(account: account, company: company, owner: sofia) }
  let(:action) do
    assignment.actions.create!(account: account, owner: sofia, kind: 'manual', reason: 'SYNTHETIC service follow-up',
                               source_key: SecureRandom.uuid, priority: 80)
  end

  before do
    account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    member.update!(custom_role: role)
    # Explicit bindings in this synthetic account; no grant is inferred from a job title.
    local = { 'enabled' => true, 'roles' => JrcRelationship::LocalRoleRules::DEFAULTS.deep_dup,
              'members' => [{ 'user_id' => sofia.id, 'role' => 'analyst', 'grants' => [], 'document_categories' => [] }] }
    JrcRelationship::Configuration.create!(account: account, rules: { 'portfolio_local_access' => local })
  end

  it 'opens the authorized panel and customer, records a result and return, and retains narrow permissions after rereading' do
    action
    hidden = JrcRelationship::Assignment.create!(account: account, owner: colleague, contact: create(:contact, account: account))
    get "#{base}/metadata", headers: headers
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body).to include('can_manage' => true, 'can_team' => false, 'can_configure' => false,
                                            'can_export' => false, 'can_manage_documents' => false)
    get "#{base}/dashboard", headers: headers, params: { mode: 'mine' }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('customers')).to eq(1)
    get "#{base}/portfolio", headers: headers, params: { mode: 'mine', per_page: 1 }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([assignment.id])
    expect(response.parsed_body.fetch('payload').first.fetch('customer_360'))
      .to eq('name' => 'jrc_customer_company', 'params' => { 'companyId' => company.id })
    get "/api/v1/accounts/#{account.id}/customers/companies/#{company.id}/overview", headers: headers
    expect(response).to have_http_status(:ok), response.body
    attendance = { request_id: SecureRandom.uuid, title: 'SYNTHETIC customer meeting', description: 'SYNTHETIC contact and result',
                   activity_type: 'meeting', contact_id: contact.id, deal_id: deal.id, completed: true }
    post "#{base}/portfolio/#{assignment.id}/manual_attendance", headers: headers, as: :json, params: { attendance: attendance }
    expect(response).to have_http_status(:created), response.body
    attendance_id = response.parsed_body.fetch('id')
    post "#{base}/portfolio/#{assignment.id}/manual_attendance", headers: headers, as: :json, params: { attendance: attendance }
    expect(response).to have_http_status(:created), response.body
    expect(response.parsed_body.fetch('id')).to eq(attendance_id)
    get "/api/v1/accounts/#{account.id}/crm/activities/#{attendance_id}", headers: headers
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body).to include('id' => attendance_id, 'status' => 'completed', 'title' => attendance.fetch(:title))
    expect(JrcCrm::Activity.find(attendance_id)).to have_attributes(user_id: sofia.id, contact_id: contact.id, deal_id: deal.id)
    get "#{base}/records/actions", headers: headers, params: { mine: true, per_page: 1 }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([action.id])

    due = 2.days.from_now.change(usec: 0)
    patch "#{base}/records/actions/#{action.id}", headers: headers, as: :json, params: { record: {
      assignment_id: assignment.id, lock_version: action.lock_version, status: 'in_progress',
      result: 'SYNTHETIC contact recorded', next_step: 'SYNTHETIC verify recovery', return_at: due.iso8601
    } }
    expect(response).to have_http_status(:ok), response.body
    expect(action.reload).to have_attributes(result: 'SYNTHETIC contact recorded', return_at: due)
    expect(action.activity.reload).to have_attributes(user_id: sofia.id, company_id: company.id, due_at: due)
    get "#{base}/records/actions/#{action.id}", headers: headers
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body).to include('result' => 'SYNTHETIC contact recorded', 'next_step' => 'SYNTHETIC verify recovery')
    expect(response.parsed_body.fetch('history').first).to include('actor_id' => sofia.id)
    %w[configuration team export].each do |destination|
      get "#{base}/#{destination}", headers: headers
      expect(response).to have_http_status(:forbidden)
    end
    get "#{base}/portfolio/#{hidden.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    role.update!(permissions: ['contact_manage'])
    get "#{base}/records/actions/#{action.id}", headers: headers
    expect(response).to have_http_status(:forbidden)
    expect(action.reload.result).to eq('SYNTHETIC contact recorded')
    expect(member.reload).to be_agent
  end
end
