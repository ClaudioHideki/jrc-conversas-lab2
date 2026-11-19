require 'rails_helper'

RSpec.describe 'Native ACW immutable form binding configuration', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:policy) { JrcContactCenter::AcwPolicy.new(account: account.reload) }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/acw_policy" }
  let(:rule) { { id: 'synthetic_form_rule', reason_code: 'order', scope: 'general', scope_id: nil, active: true, limit_seconds: 120 } }
  let(:form) do
    JrcContactCenter::AcwFormTemplate.transaction do
      row = JrcContactCenter::AcwFormTemplate.create!(account: account)
      definition = { 'fields' => [{ 'key' => 'verified', 'label' => 'SYNTHETIC verified', 'type' => 'boolean', 'required' => true }] }
      JrcContactCenter::AcwFormVersion.create!(
        account: account, acw_form_template: row, revision: 1, name: 'SYNTHETIC configured form', description: '', status: 'active',
        definition: definition, actor_account_user_id: member.id, actor_user_id: actor.id, request_id: SecureRandom.uuid
      )
      row
    end
  end
  let(:binding) { { rule_id: rule[:id], form_id: form.id.to_s, revision: 1, required_fields: [] } }
  let(:attributes) do
    { limits: { voice: 180, whatsapp: 180 }, voice_rules: [rule], voice_form_bindings: [binding], expected_revision: policy.revision }
  end
  let(:audits) { Audited.audit_class.where(associated: account, comment: JrcContactCenter::ConfigurationAudit::ACW_COMMENT) }

  before { account.enable_features!('jrc_contact_center') }

  it 'persists rules and owned exact form pins in one native revision and mandatory configuration audit' do
    patch endpoint, headers: actor.create_new_auth_token, params: attributes, as: :json
    expect(response).to have_http_status(:ok)
    pin = response.parsed_body.dig('item', 'voice_form_bindings').sole
    expect(pin).to include('form_id' => form.id.to_s, 'revision' => 1, 'required_fields' => ['verified'])
    expect(pin['integrity_sha256']).to eq(form.latest_version.integrity_sha256)
    expect(audits.sole.audited_changes.dig('attributes', 1, 'voice_form_bindings')).to eq([pin])
    expect(response.parsed_body.dig('item', 'revision')).to eq(policy.revision)
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
  end

  it 'rejects stale settings and preserves both the previous rules and form pins without a second audit' do
    initial = attributes
    patch endpoint, headers: actor.create_new_auth_token, params: initial, as: :json
    saved = account.reload.settings.deep_dup
    patch endpoint, headers: actor.create_new_auth_token, params: initial.merge(voice_form_bindings: []), as: :json
    expect(response).to have_http_status(:conflict)
    expect(account.reload.settings).to eq(saved)
    expect(audits.count).to eq(1)
  end

  it 'does not orphan a form when deleting a rule and permits only an explicit atomic removal of both' do
    patch endpoint, headers: actor.create_new_auth_token, params: attributes, as: :json
    saved = account.reload.settings.deep_dup
    changed = { limits: { voice: 180, whatsapp: 180 }, voice_rules: [], expected_revision: policy.revision }
    patch endpoint, headers: actor.create_new_auth_token, params: changed, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.reload.settings).to eq(saved)
    expect(audits.count).to eq(1)
    patch endpoint, headers: actor.create_new_auth_token, params: changed.merge(voice_form_bindings: []), as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('item', 'voice_form_bindings')).to eq([])
    expect(audits.count).to eq(2)
  end

  it 'requires a current native revision even when the only change is an explicit empty form binding collection' do
    patch endpoint, headers: actor.create_new_auth_token,
          params: { limits: { voice: 180, whatsapp: 180 }, voice_form_bindings: [] }, as: :json
    expect(response).to have_http_status(:precondition_required)
    expect(account.reload.settings).not_to have_key(JrcContactCenter::AcwPolicy::KEY)
    expect(audits).to be_empty
  end

  [nil, false, {}, [false]].each do |invalid|
    it "does not silently discard malformed binding settings #{invalid.inspect}" do
      patch endpoint, headers: actor.create_new_auth_token, params: attributes.merge(voice_form_bindings: invalid), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(audits).to be_empty
      expect(JrcContactCenter::AcwScopedRules.new(account: account.reload).call).to be_empty
    end
  end

  it 'refuses a known form ID in another account without changing either account settings' do
    foreign = create(:account)
    foreign.enable_features!('jrc_contact_center')
    other_actor = create(:user, :contact_center_eligible, account: foreign, role: :administrator)
    other_endpoint = "/api/v1/accounts/#{foreign.id}/jrc_contact_center/acw_policy"
    revision = JrcContactCenter::AcwPolicy.new(account: foreign).revision
    patch other_endpoint, headers: other_actor.create_new_auth_token, params: attributes.merge(expected_revision: revision), as: :json
    expect(response).to have_http_status(:not_found)
    expect(JrcContactCenter::AcwScopedRules.new(account: foreign.reload).call).to be_empty
    expect(audits).to be_empty
  end

  it 'does not expose configuration pins or derive configuration authority for an ordinary operator' do
    patch endpoint, headers: actor.create_new_auth_token, params: attributes, as: :json
    operator = create(:user, :contact_center_eligible, account: account, role: :agent)
    get endpoint, headers: operator.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item')).not_to have_key('voice_form_bindings')
    expect(response.body).not_to include(form.latest_version.name, 'synthetic_form_rule')
    patch endpoint, headers: operator.create_new_auth_token, params: attributes, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(audits.count).to eq(1)
  end
end
