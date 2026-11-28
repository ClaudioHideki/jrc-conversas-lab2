# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Native reviewed Relationship activity from a recording', :pabx, type: :request do
  include_context 'with native recording Relationship intake'

  let(:path) { "/api/v1/accounts/#{account.id}/jrc_contact_center/recordings/#{record.id}/relationship_activities" }

  def write_relationship(input = relationship_input, target = path)
    post target, headers: actor.create_new_auth_token, params: { relationship_activity: input }, as: :json
  end

  def activities
    JrcCrm::Activity.where(account: account)
  end

  it 'previews only authorized native portfolios and explicit caller context without creating work' do
    get path, headers: actor.create_new_auth_token
    body = response.parsed_body
    expect(response).to have_http_status(:ok)
    expect(body).to include('recording_id' => record.id.to_s, 'call_session_id' => source_call.id.to_s,
                            'contact_id' => caller_contact.id.to_s, 'user_id' => actor.id.to_s)
    expect(body.fetch('items')).to eq([{ 'id' => assignment.id.to_s, 'label' => customer.name, 'can_work' => true }])
    expect(response.headers['Cache-Control']).to include('private', 'no-store')
    expect(activities).to be_empty
    expect(response.body).not_to include('recording_reference', 'synthetic-password', 'project_id')
    expect(provider).not_to have_received(:find_analysis)
  end

  it 'persists through the native workflow, current actor, unit, source manifest and audit without completing ACW' do
    before = source_call.attributes
    write_relationship
    expect(response).to have_http_status(:created)
    activity = activities.sole
    expect(activity).to have_attributes(user_id: actor.id, activity_type: 'call', company_id: customer.id,
                                        business_unit_id: business.id, title: relationship_input.fetch('title'), status: 'scheduled')
    action = assignment.actions.sole
    expect(action.activity_id).to eq(activity.id)
    expect(action.metadata.dig('_source_ids', 'activities')).to include(activity.id)
    expect(activity.metadata.fetch('control_desk_recording_origin')).to include('recording_id' => record.id, 'contact_id' => caller_contact.id)
    expect(source_call.reload.attributes).to eq(before)
    expect(response.body).not_to include(record.external_unique_id, 'recording_reference', 'synthetic-password', 'texto_transcrito')
  end

  it 'records an explicit audit and returns a native readable target only after persistence' do
    write_relationship
    expect(response).to have_http_status(:created)
    activity = activities.sole
    expect(response.parsed_body).to include('activity_id' => activity.id.to_s, 'replayed' => false,
                                            'target' => { 'kind' => 'crm_activity', 'id' => activity.id.to_s })
    audit = JrcCrm::AuditEvent.where(account: account, event_type: 'relationship_updated').order(:id).last
    expect(audit.metadata).to include('action' => 'control_desk_activity_created')
    expect(audit.to_json).not_to include('recording_reference', 'synthetic-password', 'texto_transcrito')
  end

  it 'replays the same explicit request without duplicating native actions or activities' do
    write_relationship
    first = response.parsed_body
    write_relationship
    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include(first.except('replayed').merge('replayed' => true))
    expect(activities.pluck(:id)).to eq([first.fetch('activity_id').to_i])
    expect(assignment.actions.count).to eq(1)
  end

  it 'rejects a changed payload with the same request identity without partial changes' do
    write_relationship
    before = activities.sole.attributes
    write_relationship(relationship_input.merge('title' => 'SYNTHETIC altered retry'))
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('recording_relationship_request_conflict')
    expect(activities.sole.attributes).to eq(before)
    expect(assignment.actions.count).to eq(1)
  end

  it 'does not reuse the same request key in another authorized portfolio' do
    write_relationship
    other = assignment.dup
    other.save!
    write_relationship(relationship_input.merge('assignment_id' => other.id.to_s))
    expect(response).to have_http_status(:conflict)
    expect(activities.count).to eq(1)
    expect(other.actions).to be_empty
  end

  it 'uses the existing contact portfolio without creating a company portfolio or losing native company linkage' do
    caller_contact.update!(name: nil)
    direct = JrcRelationship::Assignment.create!(account: account, contact: caller_contact, owner: actor,
                                                 business_unit: business, status: 'active')
    get path, headers: actor.create_new_auth_token
    expect(response.parsed_body.fetch('items').find { |item| item.fetch('id') == direct.id.to_s }).to include('label' => '')
    write_relationship(relationship_input.merge('assignment_id' => direct.id.to_s))
    expect(response).to have_http_status(:created)
    expect(activities.sole).to have_attributes(contact_id: caller_contact.id, company_id: customer.id)
    expect(direct.reload).to have_attributes(contact_id: caller_contact.id, company_id: nil)
    expect(direct.actions.sole.activity_id).to eq(activities.sole.id)
  end

  it 'pages multiple authorized operational portfolios without replacing or auto-selecting any of them' do
    caller_contact.update!(company: nil)
    source_call.update!(company: nil)
    assignment.update!(company: nil, contact: caller_contact)
    20.times { assignment.dup.save! }
    unrelated = JrcRelationship::Assignment.create!(account: account, contact: create(:contact, account: account),
                                                    owner: actor, business_unit: business, status: 'active')
    get path, headers: actor.create_new_auth_token, params: { page: 2 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('meta')).to eq('page' => 2, 'per_page' => 20, 'total' => 21, 'pages' => 2)
    expect(response.parsed_body.fetch('items').length).to eq(1)
    expect(response.parsed_body.fetch('items').map { |item| item.fetch('id') }).not_to include(unrelated.id.to_s)
    expect(activities).to be_empty
  end

  %w[jrc_contact_center_recordings_listen jrc_contact_center_operate contact_manage jrc_relationship_view
     jrc_relationship_manage jrc_crm].each do |right|
    it "revalidates the current #{right} permission after preview without writes" do
      input = relationship_input.deep_dup
      role.update!(permissions: role.permissions - [right])
      write_relationship(input)
      expect(response).to have_http_status(:unauthorized)
      expect(activities).to be_empty
      expect(assignment.actions).to be_empty
    end
  end

  it 'revalidates native CRM eligibility even when the role still contains CRM permission' do
    input = relationship_input.deep_dup
    member.update!(crm_enabled: false)
    write_relationship(input)
    expect(response).to have_http_status(:unauthorized)
    expect(activities).to be_empty
  end

  it 'revalidates withdrawal from Relationship independently of the Call Center and other modules' do
    input = relationship_input.deep_dup
    member.update!(jrc_relationship_withdrawn_at: Time.current)
    write_relationship(input)
    expect(response).to have_http_status(:unauthorized)
    expect(activities).to be_empty
    expect(member.reload.permissions).to include('jrc_contact_center_operate')
  end

  it 'refuses a current customer change after preview instead of redirecting the old recording' do
    input = relationship_input.deep_dup
    caller_contact.update!(company: account.master_companies.create!(name: 'SYNTHETIC changed customer'))
    write_relationship(input)
    expect(response).to have_http_status(:unauthorized)
    expect(activities).to be_empty
  end

  it 'refuses a changed native source revision without creating a record' do
    input = relationship_input.merge('origin_revision' => 'a' * 64)
    write_relationship(input)
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('recording_relationship_source_changed')
    expect(activities).to be_empty
  end

  it 'requires the source unit mapping and current active business unit' do
    input = relationship_input.deep_dup
    business.update!(active: false)
    write_relationship(input)
    expect(response).to have_http_status(:not_found)
    expect(activities).to be_empty
  end

  it 'does not disclose or write an unauthorized colleague portfolio' do
    input = relationship_input.deep_dup
    colleague = create(:user, :contact_center_eligible, account: account)
    hidden = assignment.dup
    hidden.update!(owner: colleague)
    get path, headers: actor.create_new_auth_token
    expect(response.parsed_body.fetch('items').map { |item| item.fetch('id') }).not_to include(hidden.id.to_s)
    write_relationship(input.merge('assignment_id' => hidden.id.to_s))
    expect(response).to have_http_status(:not_found)
    expect(activities).to be_empty
  end

  it 'does not disclose or write a portfolio from another account' do
    other = create(:account)
    foreign_customer = other.master_companies.create!(name: 'SYNTHETIC foreign customer')
    hidden = JrcRelationship::Assignment.create!(account: other, company: foreign_customer, status: 'active')
    write_relationship(relationship_input.merge('assignment_id' => hidden.id.to_s))
    expect(response).to have_http_status(:not_found)
    expect(activities).to be_empty
    expect(hidden.actions).to be_empty
  end

  it 'rejects a foreign recording identifier before disclosing any foreign source or creating work' do
    foreign = record.dup
    foreign.account = create(:account)
    foreign.save!
    other_path = "/api/v1/accounts/#{account.id}/jrc_contact_center/recordings/#{foreign.id}/relationship_activities"
    write_relationship(relationship_input, other_path)
    expect(response).to have_http_status(:not_found)
    expect(activities).to be_empty
    expect(response.body).not_to include(foreign.external_unique_id)
  end

  it 'does not redirect an old portfolio request to a different operational business unit' do
    input = relationship_input.deep_dup
    other = account.jrc_crm_business_units.create!(operating_company: company, code: 'REL-B', name: 'SYNTHETIC other business')
    unit.update!(settings: unit.settings.merge('business_unit_id' => other.id))
    write_relationship(input)
    expect(response).to have_http_status(:not_found)
    expect(activities).to be_empty
    expect(assignment.actions).to be_empty
  end

  it 'keeps the original authenticated actor bound even if the native membership is reassigned' do
    input = relationship_input.deep_dup
    writer = JrcContactCenter::RecordingRelationshipWrite.new(account: account, member: member)
    replacement = reassign_native_quality_member!
    account.jrc_crm_user_business_units.where(user: replacement).find_each(&:destroy!)
    account.jrc_crm_user_business_units.create!(user: replacement, scope: 'GROUP', active: true, structure_managed: true)
    assignment.update!(owner: replacement)
    fresh = JrcContactCenter::RecordingRelationshipScope.new(account: account, member: member).preview(record.id)
    expect(fresh.fetch(:items).map { |item| item.fetch(:id) }).to include(assignment.id.to_s)
    expect { writer.call(record.id, input) }.to raise_error(Pundit::NotAuthorizedError)
    expect(activities).to be_empty
    expect(assignment.actions).to be_empty
  end

  [{ 'assignment_id' => false }, { 'request_id' => 'invalid' }, { 'title' => '' }, { 'title' => 'x' * 251 },
   { 'due_at' => '2026-02-30T10:00:00Z' }, { 'due_at' => '2026-12-18T10:00:00' }, { 'origin_revision' => [] },
   { 'account_id' => '1' }, { 'user_id' => '1' }, { 'unit_id' => '1' }].each do |change|
    it "rejects malformed or authority-injecting input #{change.inspect} without writes" do
      write_relationship(relationship_input.merge(change))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(activities).to be_empty
      expect(assignment.actions).to be_empty
    end
  end
end
