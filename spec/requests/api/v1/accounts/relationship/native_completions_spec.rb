require 'rails_helper'

RSpec.describe 'Relationship reviewed preview and manual attendance endpoints', type: :request do
  include_context 'JRC Service Desk domain'
  let(:url) { "/api/v1/accounts/#{sd_account.id}/relationship" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:company) { sd_account.master_companies.create!(name: 'Native request customer') }
  let(:assignment) { JrcRelationship::Assignment.create!(account: sd_account, company: company, owner: sd_user, status: 'active') }
  let(:pipeline) { create(:jrc_crm_pipeline, account: sd_account) }
  let(:stage) { create(:jrc_crm_stage, account: sd_account, pipeline: pipeline) }
  let(:deal) { create(:jrc_crm_deal, account: sd_account, pipeline: pipeline, stage: stage, owner: sd_user, contact: sd_contact, company: company) }
  let(:book) do
    { name: 'Preview request', trigger_kind: 'health', active: false, conditions: [],
      steps: [{ kind: 'action', title: 'Reviewed action', after_days: 0, step_key: 'reviewed' }] }
  end

  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master', 'jrc_relationship', 'jrc_crm')
    sd_contact.update!(company_id: company.id)
    assignment
  end

  it 'previews the complete draft without saving it or creating planned work' do
    post "#{url}/playbook_preview", params: { assignment_id: assignment.id, source_key: 'preview-request', playbook: book }, headers: headers,
                                    as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('state' => 'preview', 'matched' => true, 'active' => false)
    expect(response.parsed_body['steps'].first).to include('kind' => 'action', 'state' => 'planned')
    expect(JrcRelationship::Playbook).not_to exist
    expect(JrcRelationship::PlaybookExecution).not_to exist
    expect(JrcRelationship::Action).not_to exist
  end

  it 'revalidates portfolio access before exposing options or previewing a foreign customer' do
    foreign_contact = create(:contact, account: sd_foreign_account)
    foreign = JrcRelationship::Assignment.create!(account: sd_foreign_account, contact: foreign_contact)
    get "#{url}/playbook_options", params: { assignment_id: foreign.id }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    post "#{url}/playbook_preview", params: { assignment_id: foreign.id, source_key: 'foreign-preview', playbook: book }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(JrcRelationship::PlaybookExecution).not_to exist
  end

  def attendance_fields
    { request_id: 'native-attendance-request', title: 'Recorded native visit', description: 'Attendance completed',
      activity_type: 'visit', contact_id: sd_contact.id, deal_id: deal.id, completed: true }
  end

  it 'creates an actual completed CRM attendance and supports a native readback' do
    fields = attendance_fields
    post "#{url}/portfolio/#{assignment.id}/manual_attendance", params: { attendance: fields }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch('id')
    native = JrcCrm::Activity.find(id)
    expect(native).to have_attributes(status: 'completed', contact_id: sd_contact.id, deal_id: deal.id)
    expect(native.completed_at).to be_present
    get "/api/v1/accounts/#{sd_account.id}/crm/activities/#{id}", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('id' => id, 'title' => 'Recorded native visit', 'status' => 'completed')
  end

  it 'returns the same attendance on replay and rejects a changed payload without survey or message side effects' do
    fields = attendance_fields
    post "#{url}/portfolio/#{assignment.id}/manual_attendance", params: { attendance: fields }, headers: headers, as: :json
    id = response.parsed_body.fetch('id')
    post "#{url}/portfolio/#{assignment.id}/manual_attendance", params: { attendance: fields }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body['id']).to eq(id)
    post "#{url}/portfolio/#{assignment.id}/manual_attendance", params: { attendance: fields.merge(title: 'Altered replay') }, headers: headers,
                                                                as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcCrm::Activity.where(account: sd_account).count).to eq(1)
    expect(JrcRelationship::Survey).not_to exist
    expect(Message.where(account: sd_account)).not_to exist
  end

  it 'creates and versions a new configuration scope under account serialization and rechecks grants after revocation' do
    fields = { scope_key: "company:#{company.id}", version: 1, weights: JrcRelationship::Configuration::DEFAULT_WEIGHTS,
               rules: { 'playbook_flow_effects_enabled' => false } }
    patch "#{url}/configuration", params: fields, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('scope_key' => fields[:scope_key], 'version' => 2)
    config = JrcRelationship::Configuration.find_by!(account: sd_account, scope_key: fields[:scope_key])
    expect(config.versions.order(:version).pluck(:version)).to eq([1, 2])
    sd_account_user.update!(role: :agent)
    patch "#{url}/configuration", params: fields.merge(version: 2, rules: { 'playbook_flow_effects_enabled' => true }), headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(config.reload).to have_attributes(version: 2, rules: { 'playbook_flow_effects_enabled' => false })
    expect(config.versions.count).to eq(2)
  end
end
