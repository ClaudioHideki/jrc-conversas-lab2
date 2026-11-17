require 'rails_helper'
require 'csv'

RSpec.describe 'Call Center configuration audit API', type: :request do
  let(:account) { create(:account) }
  let(:operator) { create(:user, account: account, role: :administrator) }
  let!(:headers) { operator.create_new_auth_token }
  let(:member) { account.account_users.find_by!(user: operator) }
  let(:role) do
    create(:custom_role, account: account,
                         permissions: %w[jrc_contact_center_view jrc_contact_center_configure jrc_contact_center_audit jrc_contact_center_reports])
  end
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center" }
  let(:url) { "#{base}/configuration_audits" }
  let(:unit) { JrcContactCenter::Unit.create!(account: account, code: 'BASE', name: 'Local unit', kind: 'sac') }
  let(:audits) { Audited.audit_class.where(associated: account, comment: JrcContactCenter::ConfigurationAudit::COMMENT) }

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
    member.update!(custom_role: role)
  end

  it 'records the actual authenticated actor and request correlation without private settings' do
    correlation = SecureRandom.uuid
    post "#{base}/units", headers: headers.merge('X-Request-ID' => correlation),
                          params: { unit: { code: 'HTTP', name: 'HTTP local', kind: 'sac', settings: { private_token: 'DO-NOT-COPY' } } }, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch('item').fetch('id')
    audit = audits.find_by!(auditable_type: 'JrcContactCenter::Unit', auditable_id: id)
    expect(audit.user_id).to eq(operator.id)
    expect(audit.request_uuid).to eq(correlation)
    expect(audit.audited_changes.to_json).not_to include('DO-NOT-COPY')
  end

  it 'returns a scoped immutable detail without e-mail or raw configuration payloads' do
    audit = audits.find_by!(auditable: unit)
    get "#{url}/#{audit.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item')).to include('resource_type' => 'unit', 'resource_id' => unit.id, 'result' => 'recorded_locally')
    expect(response.parsed_body.fetch('item').fetch('after')).to include('name' => 'Local unit')
    expect(response.body).not_to include(operator.email)
    expect(response.headers['Cache-Control']).to eq('no-store')
  end

  it 'combines resource, action, actor and correlation filters on the authorized relation' do
    correlation = SecureRandom.uuid
    patch "#{base}/units/#{unit.id}", headers: headers.merge('X-Request-ID' => correlation),
                                      params: { unit: { name: 'Reviewed unit' } }, as: :json
    expect(response).to have_http_status(:ok)
    get url, headers: headers,
             params: { resource_type: 'unit', resource_id: unit.id, operation: 'update', actor_id: operator.id, correlation_id: correlation }
    expect(response.parsed_body.fetch('items').length).to eq(1)
    expect(response.parsed_body.fetch('items').first.fetch('after')).to include('name' => 'Reviewed unit')
  end

  it 'always paginates a new list endpoint and keeps pages disjoint' do
    23.times { |i| JrcContactCenter::Unit.create!(account: account, code: "PAGE#{i}", name: "Page #{i}", kind: 'sac') }
    get url, headers: headers, params: { resource_type: 'unit' }
    first = response.parsed_body
    expect(first.fetch('items').length).to eq(20)
    expect(first.fetch('meta')).to include('page' => 1, 'pages' => 2, 'total' => 23)
    get url, headers: headers, params: { resource_type: 'unit', page: 2 }
    second = response.parsed_body.fetch('items')
    expect(second.length).to eq(3)
    expect(first.fetch('items').pluck('id') & second.pluck('id')).to be_empty
  end

  it 'caps page size instead of returning an unbounded list' do
    template = audits.find_by!(auditable: unit)
    values = template.attributes.except('id').merge('audited_changes' => template.audited_changes)
    104.times { |i| Audited.audit_class.create!(values.merge('version' => i + 2, 'request_uuid' => SecureRandom.uuid)) }
    get url, headers: headers, params: { resource_type: 'unit', per_page: 200 }
    expect(response.parsed_body.fetch('meta')).to include('per_page' => 100, 'total' => 105)
    expect(response.parsed_body.fetch('items').length).to eq(100)
  end

  it 'rejects invalid and inverted dates without pretending there are no events' do
    [%w[2026-02-30 2026-03-01], %w[2026-03-02 2026-03-01]].each do |from, to|
      get url, headers: headers, params: { from: from, to: to }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'invalid_audit_dates')
      expect(response.parsed_body).not_to have_key('items')
    end
  end

  it 'rejects nonscalar filters instead of dropping them or broadening the query' do
    [{ from: ['2026-11-17'] }, { unit_id: [unit.id] }, { correlation_id: { value: 'x' } }, { page: ['1'] }].each do |query|
      get url, headers: headers, params: query
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'invalid_audit_filter')
      expect(response.parsed_body).not_to have_key('items')
    end
  end

  it 'uses the reporting timezone for date boundaries and emits an IANA identifier' do
    account.update!(reporting_timezone: 'America/Sao_Paulo')
    travel_to(Time.utc(2026, 11, 17, 1, 30)) { unit }
    get url, headers: headers, params: { resource_type: 'unit', resource_id: unit.id, from: '2026-11-16', to: '2026-11-16' }
    expect(response.parsed_body.fetch('items').length).to eq(1)
    expect(response.parsed_body.fetch('window')).to include('timezone' => 'America/Sao_Paulo')
    get url, headers: headers, params: { resource_type: 'unit', resource_id: unit.id, from: '2026-11-17', to: '2026-11-17' }
    expect(response.parsed_body.fetch('items')).to be_empty
  end

  it 'loads complete authorized object history rather than silently keeping a thirty-day cutoff' do
    travel_to(60.days.ago) { unit }
    get url, headers: headers, params: { resource_type: 'unit', resource_id: unit.id }
    expect(response.parsed_body.fetch('items')).to be_empty
    get url, headers: headers, params: { resource_type: 'unit', resource_id: unit.id, history: 'true' }
    expect(response.parsed_body.fetch('items').length).to eq(1)
    expect(response.parsed_body.fetch('window')).to include('history' => true, 'from' => nil, 'to' => nil)
  end

  it 'requires audit authority independently from configuration privileges' do
    role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_configure])
    get url, headers: headers
    expect(response).to have_http_status(:unauthorized)
    get "#{url}/export", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'respects the native audit flag without disabling the prior provider-event contract' do
    account.disable_features!('audit_logs')
    get url, headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to include('error' => 'native_audit_unavailable')
    get "#{base}/administration/audit", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to have_key('items')
  end

  it 'exports the verified authorized data with formula protection and separate reporting authority' do
    original = audits.find_by!(auditable: unit)
    attributes = original.attributes.except('id').merge('audited_changes' => original.audited_changes, 'request_uuid' => '=2+2', 'version' => 2)
    Audited.audit_class.create!(attributes)
    get "#{url}/export", headers: headers, params: { resource_type: 'unit', resource_id: unit.id }
    expect(response).to have_http_status(:ok)
    expect(response.headers['X-Content-SHA256']).to eq(Digest::SHA256.hexdigest(response.body))
    expect(CSV.parse(response.body, headers: true).map { |row| row['Correlação'] }).to include("'=2+2")
    role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_audit])
    get "#{url}/export", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'refuses an oversized export without returning a silently truncated file' do
    template = audits.find_by!(auditable: unit)
    values = template.attributes.except('id').merge('audited_changes' => template.audited_changes)
    1000.times { |i| Audited.audit_class.create!(values.merge('version' => i + 2, 'request_uuid' => SecureRandom.uuid)) }
    get "#{url}/export", headers: headers, params: { resource_type: 'unit', resource_id: unit.id }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('error' => 'audit_export_limit_exceeded')
    expect(response.headers['X-Content-SHA256']).to be_nil
  end

  it 'denies foreign account routes and foreign detail identifiers' do
    foreign = create(:account)
    target = JrcContactCenter::Unit.create!(account: foreign, code: 'FOREIGN', name: 'Never visible', kind: 'sac')
    audit = Audited.audit_class.find_by!(associated: foreign, auditable: target)
    get "/api/v1/accounts/#{foreign.id}/jrc_contact_center/configuration_audits", headers: headers
    expect(response).to have_http_status(:unauthorized)
    get "#{url}/#{audit.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('Never visible')
  end

  it 'presents the existing native role capability audit without inventing a second history' do
    get url, headers: headers, params: { resource_type: 'role' }
    row = response.parsed_body.fetch('items').find { |item| item['resource_id'] == role.id }
    expect(row).to include('resource_type' => 'role')
    expect(row.fetch('after').fetch('permissions')).to include('jrc_contact_center_audit')
    expect(row.fetch('before').fetch('permissions')).to eq([])
  end

  it 'does not accept unauthenticated list or detail requests' do
    audit = audits.find_by!(auditable: unit)
    get url
    expect(response).to have_http_status(:unauthorized)
    get "#{url}/#{audit.id}"
    expect(response).to have_http_status(:unauthorized)
  end

  context 'with native corporate business-unit coverage' do
    let(:company) { account.master_companies.create!(name: 'SYNTHETIC issuer', relationship_type: 'internal') }
    let(:business_a) { JrcCrm::BusinessUnit.create!(account: account, operating_company: company, code: 'A', name: 'SYNTHETIC A') }
    let(:business_b) { JrcCrm::BusinessUnit.create!(account: account, operating_company: company, code: 'B', name: 'SYNTHETIC B') }
    let(:unit) do
      JrcContactCenter::Unit.create!(
        account: account, code: 'SCOPED-A', name: 'Allowed A', kind: 'sac',
        settings: { issuer_company_id: company.id, business_unit_id: business_a.id }
      )
    end
    let(:other_unit) do
      JrcContactCenter::Unit.create!(
        account: account, code: 'SCOPED-B', name: 'Restricted B', kind: 'sac',
        settings: { issuer_company_id: company.id, business_unit_id: business_b.id }
      )
    end

    before do
      JrcCrm::UserBusinessUnit.create!(
        account: account, user: operator, scope: 'BUSINESS_UNIT', business_unit: business_a,
        company: company, active: true, structure_managed: true
      )
      unit
      other_unit
    end

    it 'lists only permitted configurations and denies a foreign-unit detail' do
      allowed = audits.find_by!(auditable: unit)
      denied = audits.find_by!(auditable: other_unit)
      get url, headers: headers
      expect(response.parsed_body.fetch('items').pluck('id')).to eq([allowed.id])
      get "#{url}/#{denied.id}", headers: headers
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('Restricted B')
    end

    it 'does not use a caller-supplied unit filter to grant query or export access' do
      get url, headers: headers, params: { unit_id: other_unit.id }
      expect(response).to have_http_status(:not_found)
      get "#{url}/export", headers: headers, params: { unit_id: other_unit.id }
      expect(response).to have_http_status(:not_found)
    end

    it 'protects the generic native audit endpoint from the same cross-unit disclosure' do
      allowed = audits.find_by!(auditable: unit)
      denied = audits.find_by!(auditable: other_unit)
      account.update!(name: 'Reviewed Account')
      ordinary = Audited.audit_class.where(auditable: account, action: 'update').order(:id).last
      get "/api/v1/accounts/#{account.id}/audit_logs", headers: headers
      expect(response).to have_http_status(:ok)
      ids = response.parsed_body.fetch('audit_logs').pluck('id')
      expect(ids).to include(allowed.id, ordinary.id)
      expect(ids).not_to include(denied.id)
      expect(response.body).not_to include('Restricted B')
    end

    it 'preserves unrelated native audit entries while hiding all CC families without audit authority' do
      account.update!(name: 'Ordinary native entry')
      ordinary = Audited.audit_class.where(auditable: account, action: 'update').order(:id).last
      role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_configure])
      get "/api/v1/accounts/#{account.id}/audit_logs", headers: headers
      body = response.parsed_body.fetch('audit_logs')
      expect(body.pluck('id')).to include(ordinary.id)
      expect(body.pluck('comment')).not_to include(*JrcContactCenter::ConfigurationAudit::COMMENTS)
    end

    it 'requires both historical and current coverage after a configuration moves between units' do
      previous = audits.where(auditable: unit).pluck(:id)
      unit.update!(settings: { issuer_company_id: company.id, business_unit_id: business_b.id })
      transition = audits.where(auditable: unit, action: 'update').order(:id).last
      get url, headers: headers, params: { resource_type: 'unit', resource_id: unit.id, history: 'true' }
      expect(response.parsed_body.fetch('items')).to be_empty
      JrcCrm::UserBusinessUnit.where(account: account, user: operator).find_each { |link| link.update!(business_unit: business_b) }
      get url, headers: headers, params: { resource_type: 'unit', resource_id: unit.id, history: 'true' }
      expect(response.parsed_body.fetch('items').pluck('id')).not_to include(*previous, transition.id)
      JrcCrm::UserBusinessUnit.create!(account: account, user: operator, scope: 'GROUP', active: true, structure_managed: true)
      get "#{url}/#{transition.id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('item').dig('scopes', 'before', 'business_unit_id')).to eq(business_a.id.to_s)
      expect(response.parsed_body.fetch('item').dig('scopes', 'after', 'business_unit_id')).to eq(business_b.id.to_s)
    end
  end
end
