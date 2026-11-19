require 'rails_helper'

RSpec.describe 'Call Center native qualification origin authority', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC ACW origin', relationship_type: 'internal') }
  let(:business_units) do
    %w[A B].map { |code| JrcCrm::BusinessUnit.create!(account: account, operating_company: company, code: code, name: "SYNTHETIC ACW #{code}") }
  end
  let(:units) do
    business_units.map do |business|
      JrcContactCenter::Unit.create!(account: account, name: business.name, code: business.code, kind: 'sac',
                                     settings: { issuer_company_id: company.id, business_unit_id: business.id })
    end
  end
  let(:queues) do
    units.map { |unit| JrcContactCenter::Queue.create!(account: account, unit: unit, name: unit.name, code: unit.code) }
  end
  let(:call) do
    JrcContactCenter::CallSession.create!(account: account, provider: 'jrc_pabx', correlation_id: SecureRandom.uuid,
                                          direction: 'inbound', status: 'connected', started_at: 2.minutes.ago, answered_at: 1.minute.ago,
                                          current_unit_id: units.first.id, current_queue_id: queues.first.id)
  end
  let(:leg) do
    JrcContactCenter::CallLeg.create!(account: account, call_session: call, account_user: member, queue: queues.first,
                                      direction: 'inbound', status: 'connected', started_at: call.started_at, answered_at: call.answered_at)
  end
  let(:record) do
    call.update!(status: 'ended', ended_at: Time.current)
    JrcContactCenter::Qualification.find_by!(account: account, account_user: member, call_session: call)
  end
  let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/qualifications/#{record.id}" }
  let(:attributes) { { qualification: { reason_code: 'order', outcome_code: 'completed', notes: 'SYNTHETIC origin completion' } } }
  let(:draft_endpoint) { "#{endpoint}/draft" }
  let(:draft_attributes) do
    { expected_draft_revision: JrcContactCenter::QualificationDraftRevision.token(record),
      qualification: { reason_code: 'order', notes: 'SYNTHETIC draft answer' } }
  end

  before do
    leg
    account.enable_features!('jrc_contact_center')
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'BUSINESS_UNIT', company: company,
                                     business_unit: business_units.first, active: true, structure_managed: true)
  end

  it 'completes owned attendance through the API when a transfer remains inside its authorized unit' do
    record
    sibling = JrcContactCenter::Queue.create!(account: account, unit: units.first, name: 'SYNTHETIC sibling', code: 'SIBLING')
    call.update!(current_queue_id: sibling.id)
    patch endpoint, headers: actor.create_new_auth_token, params: attributes, as: :json
    expect(response).to have_http_status(:ok)
    expect(record.reload).to have_attributes(reason_code: 'order', outcome_code: 'completed')
    expect(record.completed_at).to be_present
    expect(record.notes).to eq('SYNTHETIC origin completion')
  end

  it 'denies completion of a formerly visible call that is now outside the authorized business unit' do
    record
    call.update!(current_unit_id: units.last.id, current_queue_id: queues.last.id)
    patch endpoint, headers: actor.create_new_auth_token, params: attributes, as: :json
    expect(response).to have_http_status(:not_found)
    expect(record.reload).to have_attributes(completed_at: nil, reason_code: nil, notes: nil)
    expect(JrcContactCenter::AgentStateEvent.find_by!(account: account, external_event_id: "qualification:#{record.id}:pending").ended_at).to be_nil
  end

  it 'does not use a caller supplied account or user ID to expand completion authority' do
    record
    outsider = create(:user, :contact_center_eligible, account: create(:account), role: :administrator)
    data = attributes.merge(account_id: account.id, account_user_id: member.id, user_id: actor.id)
    patch endpoint, headers: outsider.create_new_auth_token, params: data, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(record.reload.completed_at).to be_nil
  end

  it 'saves and reloads a private pending answer through the native API without completing the voice attendance' do
    data = draft_attributes
    started = record.started_at
    patch draft_endpoint, headers: actor.create_new_auth_token, params: data, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(record.reload).to have_attributes(reason_code: 'order', notes: 'SYNTHETIC draft answer', started_at: started, completed_at: nil)
    expect(response.parsed_body.fetch('item').fetch('draft_revision')).to eq(JrcContactCenter::QualificationDraftRevision.token(record))
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/qualifications", headers: actor.create_new_auth_token,
                                                                        params: { call_session_id: call.id }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').find { |row| row['id'] == record.id }).to include('notes' => 'SYNTHETIC draft answer')
  end

  it 'requires the native manual revision instead of accepting an unversioned draft' do
    patch draft_endpoint, headers: actor.create_new_auth_token, params: { qualification: { notes: 'SYNTHETIC missing revision' } }, as: :json
    expect(response).to have_http_status(:precondition_required)
    expect(record.reload.notes).to be_nil
    expect(record.completed_at).to be_nil
  end

  [[:reason_code, false], [:outcome_code, 12], [:notes, []], [:reason_code, { nested: 'invalid' }]].each do |field, value|
    it "rejects a malformed #{field} #{value.class} without dropping that field and saving a partial draft" do
      data = draft_attributes.deep_merge(qualification: { field => value })
      original = record.attributes
      patch draft_endpoint, headers: actor.create_new_auth_token, params: data, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(record.reload.attributes).to eq(original)
      expect(Audited.audit_class.where(auditable: record, comment: JrcContactCenter::QualificationDraft::AUDIT_COMMENT)).to be_empty
    end
  end

  [false, 12, 'invalid', ['invalid']].each do |value|
    it "rejects a #{value.class} document as a draft instead of raising an internal error" do
      data = { expected_draft_revision: JrcContactCenter::QualificationDraftRevision.token(record), qualification: value }
      original = record.attributes
      patch draft_endpoint, headers: actor.create_new_auth_token, params: data, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(record.reload.attributes).to eq(original)
      expect(Audited.audit_class.where(auditable: record, comment: JrcContactCenter::QualificationDraft::AUDIT_COMMENT)).to be_empty
    end
  end

  it 'rejects stale draft and stale completion requests without replacing a newer answer' do
    data = draft_attributes
    patch draft_endpoint, headers: actor.create_new_auth_token, params: data, as: :json
    expect(response).to have_http_status(:ok)
    patch draft_endpoint, headers: actor.create_new_auth_token,
                          params: data.deep_merge(qualification: { notes: 'SYNTHETIC stale draft' }), as: :json
    expect(response).to have_http_status(:conflict)
    patch endpoint, headers: actor.create_new_auth_token,
                    params: attributes.merge(expected_draft_revision: data.fetch(:expected_draft_revision)), as: :json
    expect(response).to have_http_status(:conflict)
    expect(record.reload).to have_attributes(notes: 'SYNTHETIC draft answer', completed_at: nil)
  end

  it 'completes and safely repeats a completion using the exact latest manual-state revision' do
    patch draft_endpoint, headers: actor.create_new_auth_token, params: draft_attributes, as: :json
    data = attributes.merge(expected_draft_revision: response.parsed_body.fetch('item').fetch('draft_revision'))
    patch endpoint, headers: actor.create_new_auth_token, params: data, as: :json
    expect(response).to have_http_status(:ok)
    completed = record.reload.attributes
    patch endpoint, headers: actor.create_new_auth_token, params: data, as: :json
    expect(response).to have_http_status(:ok)
    expect(record.reload.attributes).to eq(completed)
    patch draft_endpoint, headers: actor.create_new_auth_token, params: draft_attributes, as: :json
    expect(response).to have_http_status(:conflict)
    expect(record.reload.attributes).to eq(completed)
  end

  it 'rejects a formerly visible native call after its current unit leaves the actor coverage' do
    data = draft_attributes
    call.update!(current_unit_id: units.last.id, current_queue_id: queues.last.id)
    patch draft_endpoint, headers: actor.create_new_auth_token, params: data, as: :json
    expect(response).to have_http_status(:not_found)
    expect(record.reload).to have_attributes(notes: nil, completed_at: nil)
    expect(response.body).not_to include('SYNTHETIC draft answer')
  end

  it 'cannot use client supplied identity, scope or completion attributes to grant authority or complete a draft' do
    data = draft_attributes.deep_merge(qualification: { account_user_id: 999_999, completed_at: Time.current, duration_seconds: 0,
                                                        started_at: 1.day.ago, acw_limit_seconds: 1 })
    data.merge!(user_id: 999_999, unit_id: units.last.id, account_id: create(:account).id)
    started = record.started_at
    patch draft_endpoint, headers: actor.create_new_auth_token, params: data, as: :json
    expect(response).to have_http_status(:ok)
    expect(record.reload).to have_attributes(account_id: account.id, account_user_id: member.id, started_at: started,
                                              completed_at: nil, duration_seconds: nil, acw_limit_seconds: 180)
  end

  it 'denies a draft after native operating eligibility is revoked' do
    data = draft_attributes
    JrcContactCenter::AccessGrant.find_by!(account: account, account_user: member).update!(eligible: false)
    patch draft_endpoint, headers: actor.create_new_auth_token, params: data, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(record.reload.notes).to be_nil
  end

  it 'denies a foreign account even when it supplies the correct manual revision and target IDs' do
    data = draft_attributes
    other = create(:user, :contact_center_eligible, account: create(:account), role: :administrator)
    patch draft_endpoint, headers: other.create_new_auth_token, params: data.merge(account_user_id: member.id), as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(record.reload.notes).to be_nil
  end

  it 'does not permit an otherwise authorized account administrator to edit another operator draft' do
    data = draft_attributes
    other = create(:user, :contact_center_eligible, account: account, role: :administrator)
    account.jrc_crm_user_business_units.create!(user: other, scope: 'GROUP', structure_managed: true)
    patch draft_endpoint, headers: other.create_new_auth_token, params: data, as: :json
    expect(response).to have_http_status(:not_found)
    expect(record.reload.notes).to be_nil
  end

  it 'uses the native Rails parameter filter to exclude private draft notes from request logs' do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    parameters = { 'qualification' => { 'notes' => 'SYNTHETIC private answer', 'reason_code' => 'order' } }
    sanitized = filter.filter(parameters)
    expect(sanitized.fetch('qualification').fetch('notes')).to eq('[FILTERED]')
    expect(sanitized.to_json).not_to include('SYNTHETIC private answer')
  end

  it 'keeps global operational blocking without exposing saved answers after access to the original unit is lost' do
    patch draft_endpoint, headers: actor.create_new_auth_token, params: draft_attributes, as: :json
    expect(response).to have_http_status(:ok)
    account.jrc_crm_user_business_units.find_by!(user: actor).update!(business_unit: business_units.last)
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/agent_state", headers: actor.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    item = response.parsed_body.fetch('item')
    expect(item).to include('eligible' => false, 'eligibility_reason' => 'tabulation_pending', 'state' => 'acw')
    pending = item.fetch('pending_qualifications').find { |row| row['id'] == record.id }
    expect(pending).to include('notes' => nil, 'reason_code' => nil, 'outcome_code' => nil)
    expect(response.body).not_to include('SYNTHETIC draft answer')
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/qualifications", headers: actor.create_new_auth_token,
                                                                        params: { call_session_id: call.id }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(record.reload.notes).to eq('SYNTHETIC draft answer')
  end
end
