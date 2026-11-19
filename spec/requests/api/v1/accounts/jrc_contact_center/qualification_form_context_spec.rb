require 'rails_helper'

RSpec.describe 'Owned native qualification form context and original corporate source', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :agent) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC form issuer', relationship_type: 'internal') }
  let(:business_units) do
    %w[A B].map { |code| JrcCrm::BusinessUnit.create!(account: account, operating_company: company, code: code, name: "SYNTHETIC form #{code}") }
  end
  let(:units) do
    business_units.map do |unit|
      JrcContactCenter::Unit.create!(account: account, code: unit.code, name: unit.name, kind: 'sac',
                                     settings: { issuer_company_id: company.id, business_unit_id: unit.id })
    end
  end
  let(:queues) do
    units.map { |unit| JrcContactCenter::Queue.create!(account: account, unit: unit, code: unit.code, name: unit.name) }
  end
  let(:definition) { { 'fields' => [{ 'key' => 'private_note', 'label' => 'SYNTHETIC private field', 'type' => 'text', 'required' => true }] } }
  # Privileged synthetic seeding only; the tested operator never receives catalogue/configuration authority.
  let(:form) do
    JrcContactCenter::AcwFormTemplate.transaction do
      row = JrcContactCenter::AcwFormTemplate.create!(account: account)
      JrcContactCenter::AcwFormVersion.create!(
        account: account, acw_form_template: row, revision: 1, name: 'SYNTHETIC scoped original form', description: '', status: 'active',
        definition: definition, actor_account_user_id: member.id, actor_user_id: actor.id, request_id: SecureRandom.uuid
      )
      row
    end
  end
  let(:rule) { { id: 'synthetic_form_rule', reason_code: 'order', scope: 'queue', scope_id: queues.first.id.to_s, active: true, limit_seconds: 120 } }
  let(:policy) { JrcContactCenter::AcwPolicy.new(account: account) }
  let(:binding) { { rule_id: rule[:id], form_id: form.id.to_s, revision: 1, required_fields: [] } }
  let(:record) do
    call = JrcContactCenter::CallSession.create!(
      account: account, provider: 'synthetic', correlation_id: SecureRandom.uuid, direction: 'inbound', status: 'ended',
      started_at: 2.minutes.ago, answered_at: 1.minute.ago, ended_at: Time.current, current_unit_id: units.first.id, current_queue_id: queues.first.id
    )
    JrcContactCenter::CallLeg.create!(account: account, call_session: call, account_user: member, queue: queues.first, direction: 'inbound',
                                      status: 'ended', started_at: call.started_at, answered_at: call.answered_at, ended_at: call.ended_at)
    JrcContactCenter::Qualification.find_by!(account: account, account_user: member, call_session: call)
  end
  let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/qualifications/#{record.id}" }

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles')
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_operate])
    member.update!(custom_role: role)
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'BUSINESS_UNIT', company: company,
                                     business_unit: business_units.first, active: true, structure_managed: true)
    queues.each { |queue| JrcContactCenter::QueueMembership.create!(account: account, queue: queue, account_user: member) }
    policy.update!({ voice: 180, whatsapp: 180 }, voice_rules: [rule], voice_form_bindings: [binding], expected_revision: policy.revision)
  end

  # Keep the actual router and exception middleware. Surface its original exception instead of an opaque HTML500 assertion.
  def raise_rendered_exception!
    exception = response.request.env['action_dispatch.exception']
    raise exception if exception
  end

  it 'provides the owned exact runtime form while denying the manager catalogue to the same operator' do
    get "#{endpoint}/form_context", headers: actor.create_new_auth_token, params: { reason_code: 'order' }
    expect(response).to have_http_status(:ok)
    item = response.parsed_body.fetch('item')
    expect(item.fetch('acw_form_context').fetch('selected')).to include('form_id' => form.id.to_s, 'revision' => 1)
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.body).not_to include('actor_user_id', 'actor_account_user_id')
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/acw_forms", headers: actor.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'persists private typed responses through the authenticated native draft API and recovers them after reload' do
    previous = JrcContactCenter::QualificationDraftRevision.token(record)
    values = { reason_code: 'order', acw_form_answers: { rule[:id] => { 'private_note' => 'SYNTHETIC retained private response' } } }
    patch "#{endpoint}/draft",
          headers: actor.create_new_auth_token,
          params: { qualification: values, expected_draft_revision: previous }, as: :json
    raise_rendered_exception!
    expect(response).to have_http_status(:ok)
    saved = response.parsed_body.fetch('item').fetch('draft_revision')
    expect(saved).not_to eq(previous)
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/qualifications",
        headers: actor.create_new_auth_token,
        params: { call_session_id: record.call_session_id }
    raise_rendered_exception!
    expect(response).to have_http_status(:ok)
    item = response.parsed_body.fetch('items').sole
    expect(item.fetch('draft_revision')).to eq(saved)
    expect(item.dig('acw_form_context', 'answers', rule[:id], 'private_note')).to eq('SYNTHETIC retained private response')
    expect(item.fetch('completed_at')).to be_nil
  end

  it 'blocks missing required answers through the actual completion API with no partial completion' do
    patch endpoint,
          headers: actor.create_new_auth_token,
          params: { qualification: { reason_code: 'order', outcome_code: 'completed' } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('invalid_acw_form_answers')
    expect(record.reload.completed_at).to be_nil
    expect(JrcContactCenter::QualificationForm.find_by!(qualification: record).answers).to eq({})
  end

  it 'denies another member even in the same account without disclosing the original definition' do
    other = create(:user, :contact_center_eligible, account: account, role: :agent)
    get "#{endpoint}/form_context", headers: other.create_new_auth_token, params: { reason_code: 'order' }
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(form.latest_version.name, 'SYNTHETIC private field')
  end

  it 'rechecks the immutable original unit after a transfer even when the current call is authorized in the new unit' do
    record
    original = JrcContactCenter::QualificationForm.find_by!(qualification: record).attributes
    record.call_session.update!(current_unit_id: units.second.id, current_queue_id: queues.second.id)
    JrcCrm::UserBusinessUnit.where(account: account, user: actor).sole.update!(business_unit: business_units.second)
    native = JrcContactCenter::AccessScope.new(user_context: { account: account, account_user: member, user: actor })
    expect(native.call_sessions.exists?(record.call_session_id)).to be(true)
    get "#{endpoint}/form_context", headers: actor.create_new_auth_token, params: { reason_code: 'order', unit_id: units.first.id }
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(form.latest_version.name, 'SYNTHETIC private field')
    expect(JrcContactCenter::QualificationForm.find_by!(qualification: record).attributes).to eq(original)
  end

  it 'does not accept an old valid draft token as authority after losing the original corporate unit' do
    revision = JrcContactCenter::QualificationDraftRevision.token(record)
    record.call_session.update!(current_unit_id: units.second.id, current_queue_id: queues.second.id)
    JrcCrm::UserBusinessUnit.where(account: account, user: actor).sole.update!(business_unit: business_units.second)
    patch "#{endpoint}/draft",
          headers: actor.create_new_auth_token,
          params: { expected_draft_revision: revision, qualification: { reason_code: 'order', notes: 'SYNTHETIC must not persist' } }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(record.reload.notes).to be_nil
    expect(JrcContactCenter::QualificationForm.find_by!(qualification: record).answers).to eq({})
  end

  it 'clears new private context after losing operate permission without granting manager access' do
    record
    viewer = create(:custom_role, account: account, permissions: ['jrc_contact_center_view'])
    member.update!(custom_role: viewer)
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/qualifications",
        headers: actor.create_new_auth_token,
        params: { call_session_id: record.call_session_id }
    raise_rendered_exception!
    expect(response).to have_http_status(:ok)
    item = response.parsed_body.fetch('items').sole
    expect(item).to include('acw_form_context_unavailable' => true)
    expect(item).not_to have_key('acw_form_context')
    expect(response.body).not_to include(form.latest_version.name)
  end
end
