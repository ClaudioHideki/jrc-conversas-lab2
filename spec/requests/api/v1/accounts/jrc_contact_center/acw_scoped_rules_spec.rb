require 'rails_helper'

RSpec.describe 'Call Center scoped voice ACW rules', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:unit) { JrcContactCenter::Unit.create!(account: account, name: 'SYNTHETIC ACW', code: 'SYNTHETIC', kind: 'sac') }
  let(:queue) { JrcContactCenter::Queue.create!(account: account, unit: unit, name: 'SYNTHETIC ACW', code: 'SYNTHETIC') }
  let(:rule) { { id: 'synthetic', reason_code: 'order', scope: 'queue', scope_id: queue.id.to_s, active: true, limit_seconds: 60 } }
  let(:policy) { JrcContactCenter::AcwPolicy.new(account: account.reload) }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/acw_policy" }
  let(:attributes) { { limits: { voice: 180, whatsapp: 180 }, voice_rules: [rule], expected_revision: policy.revision } }
  let(:audits) { Audited.audit_class.where(associated: account, comment: JrcContactCenter::ConfigurationAudit::ACW_COMMENT) }

  before { account.enable_features!('jrc_contact_center') }

  it 'saves native scoped rules with an account-bound revision and a mandatory audit' do
    old = policy.revision
    patch endpoint, headers: headers, params: attributes, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item').fetch('voice_rules')).to eq([rule.stringify_keys])
    expect(response.parsed_body.dig('item', 'revision')).not_to eq(old)
    expect(audits.sole.audited_changes.dig('attributes', 1, 'voice_rules')).to eq([rule.stringify_keys])
  end

  it 'preserves existing rules on a legacy limits-only edit without materializing or changing historical events' do
    patch endpoint, headers: headers, params: attributes, as: :json
    patch endpoint, headers: headers, params: { limits: { voice: 240, whatsapp: 300 } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(JrcContactCenter::AcwScopedRules.new(account: account.reload).call).to eq([rule.stringify_keys])
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
  end

  it 'requires a revision for scoped rule edits and rejects an outdated edit atomically' do
    old = attributes
    patch endpoint, headers: headers, params: old, as: :json
    patch endpoint, headers: headers, params: old.merge(voice_rules: []), as: :json
    expect(response).to have_http_status(:conflict)
    expect(audits.count).to eq(1)
    patch endpoint, headers: headers, params: old.except(:expected_revision), as: :json
    expect(response).to have_http_status(:precondition_required)
    expect(audits.count).to eq(1)
  end

  it 'blocks two active rules for the same reason and queue rather than using input order' do
    patch endpoint, headers: headers, params: attributes.merge(voice_rules: [rule, rule.merge(id: 'second', limit_seconds: 120)]), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('conflicting_acw_rules')
    expect(audits).to be_empty
    expect(JrcContactCenter::AcwScopedRules.new(account: account.reload).call).to be_empty
  end

  [nil, false, [false], {}, [{ active: false }]].each do |invalid|
    it "rejects malformed supplied rule collections #{invalid.inspect}" do
      patch endpoint, headers: headers, params: attributes.merge(voice_rules: invalid), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(audits).to be_empty
    end
  end

  it 'rejects a queue from another account without persisting any local setting' do
    foreign = create(:account)
    remote_unit = JrcContactCenter::Unit.create!(account: foreign, name: 'SYNTHETIC other', code: 'OTHER', kind: 'sac')
    remote_queue = JrcContactCenter::Queue.create!(account: foreign, unit: remote_unit, name: 'SYNTHETIC other', code: 'OTHER')
    patch endpoint, headers: headers, params: attributes.merge(voice_rules: [rule.merge(scope_id: remote_queue.id.to_s)]), as: :json
    expect(response).to have_http_status(:not_found)
    expect(audits).to be_empty
  end

  it 'rejects a team from another account without treating the supplied ID as authority' do
    foreign = create(:team)
    patch endpoint, headers: headers, params: attributes.merge(voice_rules: [rule.merge(scope: 'team', scope_id: foreign.id.to_s)]), as: :json
    expect(response).to have_http_status(:not_found)
    expect(audits).to be_empty
  end

  it 'does not expose global scoped rule definitions to an operator without configuration permission' do
    patch endpoint, headers: headers, params: attributes, as: :json
    operator = create(:user, :contact_center_eligible, account: account, role: :agent)
    get endpoint, headers: operator.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item')).not_to have_key('voice_rules')
    expect(response.body).not_to include('synthetic')
    patch endpoint, headers: operator.create_new_auth_token, params: attributes, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'keeps unchanged global revisions and storage compatible when no rules were ever configured' do
    before = account.settings.deep_dup
    expected = Digest::SHA256.hexdigest([JrcContactCenter::AcwPolicy::KEY, account.id, true, [180, 180]].to_json)
    get endpoint, headers: headers
    expect(response.parsed_body.dig('item', 'revision')).to eq(expected)
    expect(account.reload.settings).to eq(before)
    expect(audits).to be_empty
  end
end
