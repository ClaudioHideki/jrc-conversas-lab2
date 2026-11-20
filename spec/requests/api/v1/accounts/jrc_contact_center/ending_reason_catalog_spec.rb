require 'rails_helper'

RSpec.describe 'Native ACW ending reason catalogue configuration', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/acw_policy" }
  let(:entry) do
    { code: 'synthetic_sale', name: 'SYNTHETIC sale', category: 'SYNTHETIC sales', description: 'SYNTHETIC note', order: 0, active: true }
  end
  let(:payload) do
    {
      limits: { voice: 180, whatsapp: 180 },
      voice_reason_catalog: [entry],
      expected_revision: JrcContactCenter::AcwPolicy.new(account: account.reload).revision
    }
  end
  let(:audits) { Audited.audit_class.where(associated: account, comment: JrcContactCenter::ConfigurationAudit::ACW_COMMENT) }

  before { account.enable_features!('jrc_contact_center', 'audit_logs') }

  it 'returns an empty account-global catalogue only to an authorized configurator and disables caching' do
    get endpoint, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.parsed_body.dig('item', 'voice_reason_catalog')).to eq('version' => 0, 'entries' => [])
    expect(account.reload.settings).not_to have_key(JrcContactCenter::AcwPolicy::KEY)
  end

  it 'persists through the existing policy API and records the exact version, actor and before/after in its native audit' do
    patch endpoint, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:ok)
    returned_revision = response.parsed_body.dig('item', 'revision')
    get endpoint, headers: headers
    expect(response.parsed_body.dig('item', 'revision')).to eq(returned_revision)
    saved = response.parsed_body.dig('item', 'voice_reason_catalog')
    expect(saved).to eq('version' => 1, 'entries' => [entry.stringify_keys])
    expect(audits.sole.user_id).to eq(actor.id)
    expect(audits.sole.audited_changes.dig('attributes', 1, 'voice_reason_catalog')).to eq(saved)
    expect(JrcContactCenter::AgentStateEvent.where(account: account)).to be_empty
  end

  it 'preserves old versions in the audit and deactivates without deleting codes or qualifications' do
    patch endpoint, headers: headers, params: payload, as: :json
    second = payload.merge(
      voice_reason_catalog: [entry.merge(name: 'SYNTHETIC revised', active: false)],
      expected_revision: response.parsed_body.dig('item', 'revision')
    )
    patch endpoint, headers: headers, params: second, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('item', 'voice_reason_catalog', 'version')).to eq(2)
    expect(audits.order(:id).last.audited_changes.dig('attributes', 0, 'voice_reason_catalog', 'entries', 0, 'name')).to eq(entry[:name])
    expect(audits.order(:id).first.audited_changes.dig('attributes', 1, 'voice_reason_catalog', 'version')).to eq(1)
  end

  it 'does not create another version or audit when a confirmed configuration is repeated without changes' do
    patch endpoint, headers: headers, params: payload, as: :json
    revision = response.parsed_body.dig('item', 'revision')
    patch endpoint, headers: headers, params: payload.merge(expected_revision: revision), as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('item', 'voice_reason_catalog', 'version')).to eq(1)
    expect(audits.count).to eq(1)
  end

  it 'rejects deleting or renaming persisted codes without silently losing old references' do
    patch endpoint, headers: headers, params: payload, as: :json
    stored = account.reload.settings.deep_dup
    revision = response.parsed_body.dig('item', 'revision')
    patch endpoint, headers: headers, params: payload.merge(voice_reason_catalog: [], expected_revision: revision), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('ending_reason_deactivation_required')
    patch endpoint,
          headers: headers,
          params: payload.merge(voice_reason_catalog: [entry.merge(code: 'another')], expected_revision: revision), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.reload.settings).to eq(stored)
    expect(audits.count).to eq(1)
  end

  it 'requires the current revision, rejects a stale writer and leaves unrelated ACW policy fields unchanged' do
    initial = payload
    patch endpoint, headers: headers, params: initial.except(:expected_revision), as: :json
    expect(response).to have_http_status(:precondition_required)
    patch endpoint, headers: headers, params: initial, as: :json
    patch endpoint, headers: headers, params: initial.merge(limits: { voice: 300, whatsapp: 300 }), as: :json
    expect(response).to have_http_status(:conflict)
    expect(JrcContactCenter::AcwPolicy.new(account: account.reload).call.fetch(:limits)).to eq('voice' => 180, 'whatsapp' => 180)
    expect(audits.count).to eq(1)
  end

  [nil, false, {}, 'invalid', [false], [nil]].each do |invalid|
    it "rejects malformed catalogue #{invalid.inspect} atomically without filtering it into an empty scope" do
      patch endpoint, headers: headers, params: payload.merge(voice_reason_catalog: invalid), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.reload.settings).not_to have_key(JrcContactCenter::AcwPolicy::KEY)
      expect(audits).to be_empty
    end
  end

  [{ name: '' }, { code: ' leading' }, { active: 'true' }, { order: 1.5 }, { category: '' }, { description: nil },
   { account_id: 99 }, { name: 'N' * 121 }].each do |invalid|
    it "rejects invalid fields #{invalid.inspect} without persisting a partial change" do
      patch endpoint, headers: headers, params: payload.merge(voice_reason_catalog: [entry.merge(invalid)]), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(audits).to be_empty
      expect(account.reload.settings).not_to have_key(JrcContactCenter::AcwPolicy::KEY)
    end
  end

  it 'rejects duplicate codes and over-limit catalogues before writing or auditing' do
    patch endpoint, headers: headers, params: payload.merge(voice_reason_catalog: [entry, entry]), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    rows = Array.new(101) { |i| entry.merge(code: "synthetic_#{i}") }
    patch endpoint, headers: headers, params: payload.merge(voice_reason_catalog: rows), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(audits).to be_empty
  end

  it 'does not expose configuration or grant configure permission to an ordinary operator' do
    patch endpoint, headers: headers, params: payload, as: :json
    operator = create(:user, :contact_center_eligible, account: account, role: :agent)
    get endpoint, headers: operator.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item')).not_to have_key('voice_reason_catalog')
    expect(response.body).not_to include(entry[:name])
    revision = response.parsed_body.dig('item', 'revision')
    patch endpoint, headers: operator.create_new_auth_token, params: payload.merge(expected_revision: revision), as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(audits.count).to eq(1)
  end

  it 'denies another account even when its account ID and revision are provided' do
    foreign = create(:account)
    foreign.enable_features!('jrc_contact_center')
    revision = JrcContactCenter::AcwPolicy.new(account: foreign).revision
    patch "/api/v1/accounts/#{foreign.id}/jrc_contact_center/acw_policy",
          headers: headers,
          params: payload.merge(expected_revision: revision, account_id: foreign.id), as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(foreign.reload.settings).not_to have_key(JrcContactCenter::AcwPolicy::KEY)
    expect(audits).to be_empty
  end

  it 'withholds this global configuration from an administrator with a business-unit-only coverage' do
    patch endpoint, headers: headers, params: payload, as: :json
    company = account.master_companies.create!(name: 'SYNTHETIC issuer', relationship_type: 'internal')
    unit = JrcCrm::BusinessUnit.create!(account: account, operating_company: company, name: 'SYNTHETIC unit', code: 'SYNTHETIC')
    JrcCrm::UserBusinessUnit.create!(
      account: account, user: actor, scope: 'BUSINESS_UNIT', business_unit: unit,
      company: company, active: true, structure_managed: true
    )
    get endpoint, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item')).not_to have_key('voice_reason_catalog')
    revision = response.parsed_body.dig('item', 'revision')
    patch endpoint, headers: headers, params: payload.merge(expected_revision: revision), as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(audits.count).to eq(1)
  end

  it 'persists the bounded maximum of 100 independent codes without creating operational records' do
    rows = Array.new(100) { |i| entry.merge(code: "synthetic_#{i}", order: i) }
    patch endpoint, headers: headers, params: payload.merge(voice_reason_catalog: rows), as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('item', 'voice_reason_catalog', 'entries').length).to eq(100)
    expect(audits.count).to eq(1)
    expect(JrcContactCenter::Qualification.where(account: account)).to be_empty
  end

  %w[before after].each do |position|
    it "rejects a null #{position} a valid entry instead of accepting a partially filtered catalogue" do
      rows = position == 'before' ? [nil, entry] : [entry, nil]
      patch endpoint, headers: headers, params: payload.merge(voice_reason_catalog: rows), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.reload.settings).not_to have_key(JrcContactCenter::AcwPolicy::KEY)
      expect(audits).to be_empty
    end
  end

  it 'does not accept a query field as a replacement for the typed JSON catalogue body' do
    patch "#{endpoint}?voice_reason_catalog[]=synthetic", headers: headers, params: payload.except(:voice_reason_catalog), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.reload.settings).not_to have_key(JrcContactCenter::AcwPolicy::KEY)
    expect(audits).to be_empty
  end
end
