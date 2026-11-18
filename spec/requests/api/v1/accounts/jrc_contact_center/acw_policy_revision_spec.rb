require 'rails_helper'

RSpec.describe 'Call Center expected global ACW revision', type: :request do
  let(:account) { create(:account) }
  let(:operator) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let!(:headers) { operator.create_new_auth_token }
  let(:member) { account.account_users.find_by!(user: operator) }
  let(:role) { create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_configure]) }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/acw_policy" }
  let(:limits) { { voice: 120, whatsapp: 240 } }
  let(:revision) { JrcContactCenter::AcwPolicy.new(account: account.reload).revision }
  let(:audits) { Audited.audit_class.where(associated: account, comment: JrcContactCenter::ConfigurationAudit::ACW_COMMENT) }

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles')
    member.update!(custom_role: role)
  end

  it 'returns an account-bound revision without unrelated settings and disables caching' do
    account.update!(settings: account.settings.merge('private_setting' => 'SYNTHETIC-NOT-PUBLIC'))
    get endpoint, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item')).to include('id' => account.id.to_s, 'revision' => revision)
    expect(revision).to match(/\A[a-f0-9]{64}\z/)
    expect(response.body).not_to include('SYNTHETIC-NOT-PUBLIC', 'private_setting')
    expect(response.headers['Cache-Control']).to eq('no-store')
  end

  it 'commits a current snapshot and returns a fresh revision with the audit intact' do
    expected = revision
    patch endpoint, headers: headers, params: { limits: limits, voice_required: false, expected_revision: expected }, as: :json
    expect(response).to have_http_status(:ok)
    latest = JrcContactCenter::AcwPolicy.new(account: account.reload).revision
    expect(response.parsed_body.fetch('item')).to include('voice_required' => false, 'revision' => latest)
    expect(latest).not_to eq(expected)
    expect(audits.count).to eq(1)
  end

  it 'rejects an outdated edit without changing values or appending a second audit' do
    expected = revision
    patch endpoint, headers: headers, params: { limits: limits, expected_revision: expected }, as: :json
    patch endpoint, headers: headers, params: { limits: { voice: 300, whatsapp: 360 }, expected_revision: expected }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('stale_configuration_revision')
    expect(account.reload.settings.fetch(JrcContactCenter::AcwPolicy::KEY)).to include('voice' => 120, 'whatsapp' => 240)
    expect(audits.count).to eq(1)
  end

  it 'permits a reviewed fresh snapshot and preserves explicit false' do
    expected = revision
    patch endpoint, headers: headers, params: { limits: limits, voice_required: false, expected_revision: expected }, as: :json
    get endpoint, headers: headers
    latest = response.parsed_body.fetch('item').fetch('revision')
    patch endpoint, headers: headers, params: { limits: { voice: 300, whatsapp: 360 }, expected_revision: latest }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item')).to include('voice_required' => false)
    expect(audits.count).to eq(2)
  end

  it 'does not invalidate ACW because unrelated account settings changed' do
    expected = revision
    account.update!(settings: account.settings.merge('other' => 'SYNTHETIC-preserved'))
    patch endpoint, headers: headers, params: { limits: limits, expected_revision: expected }, as: :json
    expect(response).to have_http_status(:ok)
    expect(account.reload.settings.fetch('other')).to eq('SYNTHETIC-preserved')
  end

  it 'rejects another account revision without granting authority' do
    other = create(:account)
    expected = JrcContactCenter::AcwPolicy.new(account: other).revision
    patch endpoint, headers: headers, params: { limits: limits, expected_revision: expected }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(audits).to be_empty
  end

  [nil, '', false].each do |invalid|
    it "rejects a supplied invalid precondition #{invalid.inspect} while preserving legacy omission" do
      patch endpoint, headers: headers, params: { limits: limits, expected_revision: invalid }, as: :json
      expect(response).to have_http_status(:precondition_required)
      expect(audits).to be_empty
      patch endpoint, headers: headers, params: { limits: limits }, as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  it 'rechecks permission before considering a formerly valid revision' do
    expected = revision
    role.update!(permissions: ['jrc_contact_center_view'])
    patch endpoint, headers: headers, params: { limits: limits, expected_revision: expected }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(audits).to be_empty
  end
end
