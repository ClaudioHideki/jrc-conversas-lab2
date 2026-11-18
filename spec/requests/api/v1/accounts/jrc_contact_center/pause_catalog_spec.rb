require 'rails_helper'

RSpec.describe 'Call Center account-local pause catalog API', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:headers) { actor.create_new_auth_token }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/pause_catalog" }
  let(:catalog) { JrcContactCenter::PauseCatalog.new(account: account) }
  let(:entry) do
    { code: 'synthetic_break', name: 'SYNTHETIC API pause', category: 'SYNTHETIC', active: true,
      minimum_minutes: 15, default_minutes: 30, maximum_minutes: 60, unit_ids: [], custom_role_ids: [] }
  end

  let(:payload) { { pause_catalog: { enforced: false, entries: [entry] }, expected_revision: catalog.revision } }

  before { account.enable_features!('jrc_contact_center', 'audit_logs') }

  it 'reads a disabled empty configuration with an Account-bound revision and no-store' do
    get endpoint, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(response.parsed_body.fetch('item')).to include('id' => account.id.to_s, 'enforced' => false, 'entries' => [])
    expect(response.parsed_body.dig('item', 'revision')).to match(/\A[a-f0-9]{64}\z/)
  end

  it 'persists a draft through the native authenticated endpoint without enabling the requirement' do
    patch endpoint, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:ok)
    get endpoint, headers: headers
    expect(response.parsed_body.dig('item', 'enforced')).to be(false)
    expect(response.parsed_body.dig('item', 'entries').sole).to include('code' => 'synthetic_break', 'default_minutes' => 30)
    trail = Audited.audit_class.where(associated: account, comment: JrcContactCenter::ConfigurationAudit::PAUSE_COMMENT)
    expect(trail.sole.user_id).to eq(actor.id)
  end

  it 'requires a revision and rejects an old one without creating an audit for the denied write' do
    payload = { pause_catalog: { enforced: false, entries: [entry] } }
    patch endpoint, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:precondition_required)
    expect(account.reload.settings).not_to have_key(JrcContactCenter::PauseCatalog::KEY)
    patch endpoint, headers: headers, params: payload.merge(expected_revision: '0' * 64), as: :json
    expect(response).to have_http_status(:conflict)
    expect(Audited.audit_class.where(associated: account, comment: JrcContactCenter::ConfigurationAudit::PAUSE_COMMENT)).to be_empty
  end

  it 'requires literal explicit confirmation before enabling, then preserves that choice after reload' do
    payload = { pause_catalog: { enforced: true, entries: [entry] }, expected_revision: catalog.revision }
    patch endpoint, headers: headers, params: payload.merge(activation_confirmed: 'true'), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.reload.settings).not_to have_key(JrcContactCenter::PauseCatalog::KEY)
    patch endpoint, headers: headers, params: payload.merge(activation_confirmed: true), as: :json
    expect(response).to have_http_status(:ok)
    get endpoint, headers: headers
    expect(response.parsed_body.dig('item', 'enforced')).to be(true)
  end

  it 'denies a native agent instead of treating a catalog role filter as configure authority' do
    agent = create(:user, :contact_center_eligible, account: account, role: :agent)
    auth = agent.create_new_auth_token
    get endpoint, headers: auth
    expect(response).to have_http_status(:unauthorized)
    patch endpoint, headers: auth, params: payload, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(account.reload.settings).not_to have_key(JrcContactCenter::PauseCatalog::KEY)
  end

  it 'denies an administrator constrained to a business unit for this account-global setting' do
    company = account.master_companies.create!(name: 'SYNTHETIC scoped issuer', relationship_type: 'internal')
    unit = JrcCrm::BusinessUnit.create!(account: account, operating_company: company, name: 'SYNTHETIC unit', code: 'SYNTHETIC')
    JrcCrm::UserBusinessUnit.create!(account: account, user: actor, scope: 'BUSINESS_UNIT', business_unit: unit,
                                     company: company, active: true, structure_managed: true)
    get endpoint, headers: headers
    expect(response).to have_http_status(:unauthorized)
    patch endpoint, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(account.reload.settings).not_to have_key(JrcContactCenter::PauseCatalog::KEY)
  end

  it 'rejects a Unit from another account without persisting configuration or returning its contents' do
    foreign = JrcContactCenter::Unit.create!(account: create(:account), code: 'SYNTHETIC', name: 'SYNTHETIC foreign', kind: 'sac')
    payload = { pause_catalog: { enforced: false, entries: [entry.merge(unit_ids: [foreign.id])] }, expected_revision: catalog.revision }
    patch endpoint, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(foreign.name)
    expect(account.reload.settings).not_to have_key(JrcContactCenter::PauseCatalog::KEY)
  end

  %w[false_row false_code malformed_units].each do |shape|
    it "rejects malformed configuration #{shape} instead of filtering it into an unrestricted entry" do
      malformed = case shape
                  when 'false_row' then false
                  when 'false_code' then entry.merge(code: false)
                  else entry.merge(unit_ids: { arbitrary: 1 })
                  end
      malformed_payload = payload.deep_merge(pause_catalog: { entries: [malformed] })
      patch endpoint, headers: headers, params: malformed_payload, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.reload.settings).not_to have_key(JrcContactCenter::PauseCatalog::KEY)
    end
  end

  it 'returns the exact inconsistent field and preserves the draft response boundary' do
    invalid = entry.merge(maximum_minutes: 10)
    invalid_payload = payload.deep_merge(pause_catalog: { entries: [invalid] })
    patch endpoint, headers: headers, params: invalid_payload, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('invalid_attributes')).to include('maximum_minutes')
    expect(account.reload.settings).not_to have_key(JrcContactCenter::PauseCatalog::KEY)
  end

  it 'does not accept another account membership or a forged body account as authority' do
    other = create(:account)
    outsider = create(:user, :contact_center_eligible, account: other, role: :administrator)
    patch endpoint, headers: outsider.create_new_auth_token, params: payload.merge(account_id: account.id), as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(account.reload.settings).not_to have_key(JrcContactCenter::PauseCatalog::KEY)
  end

  it 'keeps catalog audit separate from the ACW subtype and protects it with native audit authority' do
    account.enable_features!('custom_roles')
    role = create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_configure jrc_contact_center_audit])
    member = account.account_users.find_by!(user: actor)
    member.update!(custom_role: role)
    patch endpoint, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:ok)
    context = { account: account, account_user: member.reload, user: actor }
    catalog_rows = JrcContactCenter::ConfigurationAuditQuery.new(context: context, params: { resource_type: 'pause_catalog' }).call
    expect(catalog_rows.pluck(:comment)).to eq([JrcContactCenter::ConfigurationAudit::PAUSE_COMMENT])
    acw_rows = JrcContactCenter::ConfigurationAuditQuery.new(context: context, params: { resource_type: 'acw_policy' }).call
    expect(acw_rows).to be_empty
    role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_configure])
    context[:account_user].reload
    protected_rows = JrcContactCenter::ConfigurationAuditScope.protect_native_list(Audited.audit_class.where(associated: account), context)
    expect(protected_rows.where(comment: JrcContactCenter::ConfigurationAudit::PAUSE_COMMENT)).to be_empty
  end
end
