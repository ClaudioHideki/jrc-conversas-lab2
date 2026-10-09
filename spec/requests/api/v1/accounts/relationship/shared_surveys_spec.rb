require 'rails_helper'

RSpec.describe 'Relationship survey administration and handoff boundaries', type: :request do
  include_context 'JRC Service Desk domain'
  let(:url) { "/api/v1/accounts/#{sd_account.id}/relationship" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:company) { sd_account.master_companies.create!(name: 'Authorized customer') }
  let(:assignment) { JrcRelationship::Assignment.create!(account: sd_account, company: company, owner: sd_user) }
  let(:definition_fields) do
    { name: 'NPS draft', code: 'draft_nps', kind: 'nps', status: 'draft',
      questions: [{ key: 'rating', text: 'Published wording', type: 'scale', min: 0, max: 10, required: true }],
      settings: { recovery_enabled: false } }
  end

  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm', 'jrc_projects')
    sd_contact.update!(company_id: company.id)
    assignment
  end

  it 'creates a draft, records immutable history and rejects stale edits' do
    post "#{url}/survey_administration/definitions", params: { record: definition_fields }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch('id')
    patch "#{url}/survey_administration/definitions/#{id}", params: { record: { name: 'Version two', version: 1 } }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    patch "#{url}/survey_administration/definitions/#{id}", params: { record: { name: 'Stale version', version: 1 } }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    get "#{url}/survey_administration/definitions/#{id}/history", headers: headers, as: :json
    expect(response.parsed_body['payload'].pluck('version')).to eq([2, 1])
    expect(JrcRelationship::Survey.where(account: sd_account)).not_to exist
  end

  it 'blocks a normal agent from administering account-wide definitions and rules' do
    sd_account_user.update!(role: :agent)
    get "#{url}/survey_administration/definitions", headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    post "#{url}/survey_administration/definitions", params: { record: definition_fields }, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(JrcRelationship::SurveyDefinition.where(account: sd_account)).not_to exist
  end

  it 'rejects foreign account definitions and unpublished scale tampering' do
    foreign = JrcRelationship::SurveyDefinition.create!(account: sd_foreign_account, **definition_fields)
    get "#{url}/survey_administration/definitions/#{foreign.id}/history", headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    fields = definition_fields.deep_dup
    fields[:questions].first[:max] = 100
    post "#{url}/survey_administration/definitions", params: { record: fields }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'revalidates native source visibility and does not schedule or send during preview' do
    source = create(:conversation, account: sd_account, contact: sd_contact, assignee: sd_user, status: :resolved)
    fields = { source_type: source.class.name, source_id: source.id, cycle_key: 'preview-only' }
    expect do
      post "#{url}/survey_policy_preview", params: fields, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['reason']).to eq('rule_missing')
    end.not_to change(JrcRelationship::SurveyDispatchDecision, :count)
    expect(JrcRelationship::Survey.where(account: sd_account)).not_to exist
  end

  it 'accepts a real completed project handoff once and keeps the decision history immutable' do
    project = JrcProjects::Project.create!(account: sd_account, owner: sd_user, contact: sd_contact, key: 'READY', name: 'Completed implementation',
                                           status: 'completed', visibility: 'account')
    post "#{url}/handoffs", params: { assignment_id: assignment.id, source_type: project.class.name, source_id: project.id }, headers: headers,
                            as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch('id')
    fields = { status: 'accepted', reason: 'Reviewed native context',
               checklist: %w[contract products contacts objectives promises pending_items].index_with(true) }
    post "#{url}/handoffs/#{id}/decide", params: fields, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    post "#{url}/handoffs/#{id}/decide", params: fields.merge(reason: 'Change decision'), headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    row = JrcRelationship::HandoffCase.find(id)
    expect(row.status).to eq('accepted')
    expect(row.decided_by_id).to eq(sd_user.id)
    expect(row.reason).to eq('Reviewed native context')
    expect { row.update!(reason: 'Changed') }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'blocks a foreign project and acceptance before every handoff item is reviewed' do
    project = JrcProjects::Project.create!(account: sd_account, owner: sd_user, contact: sd_contact, key: 'WAIT', name: 'Completed implementation',
                                           status: 'completed', visibility: 'account')
    post "#{url}/handoffs", params: { assignment_id: assignment.id, source_type: project.class.name, source_id: project.id }, headers: headers,
                            as: :json
    id = response.parsed_body.fetch('id')
    post "#{url}/handoffs/#{id}/decide", params: { status: 'accepted', reason: 'Incomplete review', checklist: { contract: true } },
                                         headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcRelationship::HandoffCase.find(id).status).to eq('pending')
    foreign = JrcProjects::Project.create!(account: sd_foreign_account, owner: create(:user, account: sd_foreign_account), key: 'OTHER',
                                           name: 'Other tenant',
                                           status: 'completed', visibility: 'account')
    post "#{url}/handoffs", params: { assignment_id: assignment.id, source_type: foreign.class.name, source_id: foreign.id }, headers: headers,
                            as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'starts the gated native onboarding only after formal acceptance and remains idempotent on later events' do
    assignment.destroy!
    JrcRelationship::Configuration.create!(account: sd_account, rules: { 'handoff_acceptance_required' => true })
    order = JrcCrm::SalesOrder.create!(account: sd_account, owner: sd_user, contact: sd_contact, source_type: 'manual',
                                       order_origin: 'direct_sale', status: 'completed')
    gated = JrcRelationship::Handoff.call(order, actor: sd_user)
    row = JrcRelationship::HandoffCase.find_by!(assignment: gated, source_id: order.id)
    expect(gated.actions).not_to exist
    post "#{url}/handoffs/#{row.id}/decide", params: { status: 'accepted', reason: 'Native context reviewed',
                                                       checklist: %w[contract products contacts objectives promises pending_items].index_with(true) },
                                             headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(gated.reload.status).to eq('active')
    expect(gated.actions.where(source_key: 'handoff').count).to eq(1)
    before = gated.actions.count
    JrcRelationship::Handoff.call(order, actor: sd_user)
    expect(gated.actions.count).to eq(before)
    expect(row.reload.decided_by_id).to eq(sd_user.id)
  end

  it 'requires an audited manager exception for a new portfolio without strict commercial evidence' do
    JrcRelationship::Configuration.create!(account: sd_account, rules: { 'eligibility_mode' => 'active_contract_product' })
    other = sd_account.master_companies.create!(name: 'Customer with explicit exception')
    fields = { company_id: other.id, owner_id: sd_user.id }
    post "#{url}/portfolio", params: { assignment: fields }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    fields[:exception_reason] = 'Approved pilot with documented commercial follow-up'
    post "#{url}/portfolio", params: { assignment: fields }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    row = JrcRelationship::Assignment.find(response.parsed_body.fetch('id'))
    expect(row.settings['eligibility_exception']).to include('reason' => fields[:exception_reason], 'approved_by_id' => sd_user.id)
    expect(JrcCrm::AuditEvent.where(account: sd_account, resource_type: row.class.name, resource_id: row.id)
                           .where("metadata ->> 'action' = 'eligibility_exception_approved'")).to exist
    sd_account_user.update!(role: :agent)
    another = sd_account.master_companies.create!(name: 'Unauthorized exception customer')
    post "#{url}/portfolio", params: { assignment: fields.merge(company_id: another.id) }, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(JrcRelationship::Assignment.where(company: another)).not_to exist
  end
end
