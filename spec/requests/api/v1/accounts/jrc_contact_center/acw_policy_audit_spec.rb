require 'rails_helper'

RSpec.describe 'Call Center local ACW configuration audit', type: :request do
  let(:account) { create(:account) }
  let(:operator) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let!(:headers) { operator.create_new_auth_token }
  let(:member) { account.account_users.find_by!(user: operator) }
  let(:role) do
    create(:custom_role, account: account,
                         permissions: %w[jrc_contact_center_view jrc_contact_center_configure jrc_contact_center_audit jrc_contact_center_reports])
  end
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center" }
  let(:audits) { Audited.audit_class.where(associated: account, comment: JrcContactCenter::ConfigurationAudit::ACW_COMMENT) }
  let(:limits) { { voice: 120, whatsapp: 240 } }

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
    member.update!(custom_role: role)
  end

  it 'records effective values and the authenticated actor and request correlation atomically' do
    correlation = SecureRandom.uuid
    patch "#{base}/acw_policy", headers: headers.merge('X-Request-ID' => correlation),
                                params: { limits: limits, voice_required: false }, as: :json
    expect(response).to have_http_status(:ok)
    record = audits.sole
    expect(record.attributes).to include('auditable_type' => 'Account', 'auditable_id' => account.id, 'user_id' => operator.id)
    expect(record.request_uuid).to eq(correlation)
    expected = [
      { 'voice' => 180, 'whatsapp' => 180, 'voice_required' => true },
      { 'voice' => 120, 'whatsapp' => 240, 'voice_required' => false }
    ]
    expect(record.audited_changes.fetch('attributes')).to eq(expected)
    expect(account.reload.settings.fetch(JrcContactCenter::AcwPolicy::KEY)).to include('voice_required' => false, 'voice' => 120)
  end

  it 'does not append misleading events for an unchanged effective default or a repeated save' do
    patch "#{base}/acw_policy", headers: headers, params: { limits: { voice: 180, whatsapp: 180 } }, as: :json
    expect(audits.count).to eq(0)
    2.times { patch "#{base}/acw_policy", headers: headers, params: { limits: limits }, as: :json }
    expect(response).to have_http_status(:ok)
    expect(audits.count).to eq(1)
  end

  it 'exposes the same native event in filtered history and detail without private account settings' do
    account.update!(settings: account.settings.merge('unrelated_secret' => 'SYNTHETIC-DO-NOT-COPY'))
    patch "#{base}/acw_policy", headers: headers, params: { limits: limits }, as: :json
    query = { resource_type: 'acw_policy', resource_id: account.id, history: 'true' }
    get "#{base}/configuration_audits", headers: headers, params: query
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([audits.sole.id])
    get "#{base}/configuration_audits/#{audits.sole.id}", headers: headers
    expect(response.parsed_body.fetch('item')).to include('resource_type' => 'acw_policy', 'resource_id' => account.id)
    expect(response.parsed_body.fetch('item').fetch('after')).to include('voice' => 120, 'whatsapp' => 240)
    expect(response.body).not_to include('SYNTHETIC-DO-NOT-COPY', operator.email)
    expect(response.headers['Cache-Control']).to eq('no-store')
    expect(account.reload.settings.fetch('unrelated_secret')).to eq('SYNTHETIC-DO-NOT-COPY')
  end

  it 'rejects invalid limits without changing the policy or appending an event' do
    previous = account.reload.settings
    patch "#{base}/acw_policy", headers: headers, params: { limits: { voice: 0, whatsapp: 9000 } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.reload.settings).to eq(previous)
    expect(audits).to be_empty
  end

  it 'preserves account settings when the mandatory audit insertion fails' do
    previous = account.reload.settings
    allow(JrcContactCenter::AcwPolicyAudit).to receive(:write!).and_raise(ActiveRecord::StatementInvalid, 'SYNTHETIC audit unavailable')
    expect do
      # Separate application boundary inside RSpec's enclosing fixture transaction.
      Account.transaction(requires_new: true) { JrcContactCenter::AcwPolicy.new(account: account).update!(limits) }
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(account.reload.settings).to eq(previous)
    expect(audits).to be_empty
  end

  it 'omits malformed legacy field content rather than copying it into the new audit' do
    account.update!(settings: account.settings.merge(JrcContactCenter::AcwPolicy::KEY => { 'voice' => 'SYNTHETIC-PRIVATE-LEGACY' }))
    patch "#{base}/acw_policy", headers: headers, params: { limits: limits }, as: :json
    expect(response).to have_http_status(:ok)
    expect(audits.sole.audited_changes.fetch('omitted_fields')).to eq(['voice'])
    expect(audits.sole.audited_changes.fetch('attributes').first).not_to have_key('voice')
    expect(audits.sole.audited_changes.to_json).not_to include('SYNTHETIC-PRIVATE-LEGACY')
  end

  it 'requires audit permission independently of global configure authority' do
    patch "#{base}/acw_policy", headers: headers, params: { limits: limits }, as: :json
    id = audits.sole.id
    role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_configure])
    get "#{base}/configuration_audits/#{id}", headers: headers
    expect(response).to have_http_status(:unauthorized)
    get "/api/v1/accounts/#{account.id}/audit_logs", headers: headers
    expect(response.parsed_body.fetch('audit_logs').pluck('id')).not_to include(id)
    expect(audits.count).to eq(1)
  end

  it 'keeps native audit feature gating while still recording a successful local configuration change' do
    account.disable_features!('audit_logs')
    patch "#{base}/acw_policy", headers: headers, params: { limits: limits }, as: :json
    expect(response).to have_http_status(:ok)
    expect(audits.count).to eq(1)
    get "#{base}/configuration_audits/#{audits.sole.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to include('error' => 'native_audit_unavailable')
  end

  it 'denies another account route and another accounts event identifier' do
    foreign = create(:account)
    JrcContactCenter::AcwPolicy.new(account: foreign).update!(limits)
    record = Audited.audit_class.find_by!(associated: foreign, comment: JrcContactCenter::ConfigurationAudit::ACW_COMMENT)
    get "#{base}/configuration_audits/#{record.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    patch "/api/v1/accounts/#{foreign.id}/jrc_contact_center/acw_policy", headers: headers, params: { limits: limits }, as: :json
    expect(response).to have_http_status(:unauthorized)
    get "#{base}/configuration_audits", headers: headers, params: { resource_type: 'acw_policy' }
    expect(response.parsed_body.fetch('items')).to be_empty
    expect(audits).to be_empty
  end

  it 'does not expose or mutate an account-wide policy through a business-unit grant' do
    patch "#{base}/acw_policy", headers: headers, params: { limits: limits }, as: :json
    id = audits.sole.id
    company = account.master_companies.create!(name: 'SYNTHETIC issuer', relationship_type: 'internal')
    unit = JrcCrm::BusinessUnit.create!(account: account, operating_company: company, code: 'SYNTHETIC-A', name: 'SYNTHETIC A')
    JrcCrm::UserBusinessUnit.create!(
      account: account, user: operator, scope: 'BUSINESS_UNIT', business_unit: unit,
      company: company, active: true, structure_managed: true
    )
    get "#{base}/configuration_audits/#{id}", headers: headers
    expect(response).to have_http_status(:not_found)
    get "#{base}/configuration_audits", headers: headers, params: { resource_type: 'acw_policy' }
    expect(response.parsed_body.fetch('items')).to be_empty
    get "/api/v1/accounts/#{account.id}/audit_logs", headers: headers
    expect(response.parsed_body.fetch('audit_logs').pluck('id')).not_to include(id)
    patch "#{base}/acw_policy", headers: headers, params: { limits: { voice: 60, whatsapp: 60 } }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::AcwPolicy.new(account: account.reload).call.fetch(:limits)).to eq('voice' => 120, 'whatsapp' => 240)
    expect(audits.count).to eq(1)
  end
end
