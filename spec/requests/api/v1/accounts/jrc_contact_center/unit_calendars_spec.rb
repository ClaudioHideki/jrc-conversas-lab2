require 'rails_helper'

RSpec.describe 'Call Center internal unit calendars retain native scope, revision and audit', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let!(:headers) { actor.create_new_auth_token }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC calendar issuer', relationship_type: 'internal') }
  let(:business) do
    %w[A B].map { |code| account.jrc_crm_business_units.create!(operating_company: company, code: code, name: "SYNTHETIC #{code}") }
  end
  let(:units) do
    business.map do |row|
      JrcContactCenter::Unit.create!(account: account, code: row.code, name: row.name, kind: 'sac',
                                     settings: { issuer_company_id: company.id, business_unit_id: row.id })
    end
  end
  let(:unit) { units.first }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center/unit_calendars" }
  let(:definition) do
    { 'name' => 'SYNTHETIC internal schedule', 'description' => '', 'timezone' => 'America/Sao_Paulo',
      'weekly' => (1..7).to_h { |day| [day.to_s, day <= 5 ? [['08:00', '12:00'], ['13:00', '17:00']] : []] },
      'holidays' => [{ 'date' => '2026-11-23', 'name' => 'SYNTHETIC holiday', 'kind' => 'internal', 'type' => 'movable' }],
      'exceptions' => [{ 'date' => '2026-11-23', 'name' => 'SYNTHETIC duty', 'intervals' => [['10:00', '11:00']] }] }
  end
  let(:entry) { { 'id' => SecureRandom.uuid, 'active' => true, 'definition' => definition } }
  let(:body) do
    { unit_id: unit.id.to_s, expected_revision: JrcContactCenter::ConfigurationRevision.token(unit.reload), calendar: entry }
  end

  before do
    account.enable_features!('jrc_contact_center', 'audit_logs', 'custom_roles')
    member.update!(custom_role: create(:custom_role, account: account,
                                                     permissions: %w[jrc_contact_center_view jrc_contact_center_configure jrc_contact_center_audit]))
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: company,
                                                business_unit: business.first, active: true, structure_managed: true)
  end

  it 'returns an empty authorized catalog without creating default calendars or publishing anything' do
    get base, headers: headers, params: { unit_id: unit.id.to_s }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('items' => [], 'local_only' => true, 'pabx_confirmed' => false)
    expect(response.parsed_body.fetch('revision')).to match(/\A[a-f0-9]{64}\z/)
    expect(response.headers['Cache-Control']).to eq('no-store')
    expect(unit.reload.settings).not_to have_key(JrcContactCenter::CalendarCatalogState::KEY)
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  it 'persists a named calendar in the existing unit and records scoped native before and after evidence' do
    post base, headers: headers, params: body, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.fetch('item')).to eq(entry)
    state = unit.reload.settings.fetch(JrcContactCenter::CalendarCatalogState::KEY)
    expect(state).to include('version' => 1, 'entries' => [entry])
    audit = Audited.audit_class.where(auditable: unit, action: 'update').last
    expect(audit.audited_changes.dig('attributes', 1, 'settings', JrcContactCenter::CalendarCatalogState::KEY)).to eq(state)
    expect(audit.audited_changes.dig('cc_scope', 'after', 'unit_id')).to eq(unit.id.to_s)
    expect([audit.user_id, audit.request_uuid.present?]).to eq([actor.id, true])
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  it 'recovers the same committed identity after a lost creation response without another row, revision or audit' do
    input = body
    post base, headers: headers, params: input, as: :json
    expect(response).to have_http_status(:created)
    first = response.parsed_body
    audit_count = Audited.audit_class.where(auditable: unit).count
    post base, headers: headers, params: input, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to eq(first)
    expect(unit.reload.settings.fetch(JrcContactCenter::CalendarCatalogState::KEY)).to include('version' => 1, 'entries' => [entry])
    expect(Audited.audit_class.where(auditable: unit).count).to eq(audit_count)
  end

  it 'updates only after the reviewed native revision and rejects a stale edit without losing the committed definition' do
    input = body
    post base, headers: headers, params: input, as: :json
    created = response.parsed_body
    reviewed = input.merge(expected_revision: created.fetch('revision'),
                           calendar: entry.deep_merge('definition' => { 'name' => 'SYNTHETIC current' }))
    patch "#{base}/#{entry.fetch('id')}", headers: headers, params: reviewed, as: :json
    expect(response).to have_http_status(:ok)
    patch "#{base}/#{entry.fetch('id')}", headers: headers, params: reviewed, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('stale_configuration_revision')
    state = unit.reload.settings.fetch(JrcContactCenter::CalendarCatalogState::KEY)
    expect(state.fetch('entries').sole.dig('definition', 'name')).to eq('SYNTHETIC current')
    expect(state.fetch('version')).to eq(2)
  end

  it 'does not grant another native unit through a body identifier or disclose its calendar' do
    input = body
    get base, headers: headers, params: { unit_id: units.last.id.to_s }
    expect(response).to have_http_status(:not_found)
    post base, headers: headers, params: input.merge(unit_id: units.last.id.to_s), as: :json
    expect(response).to have_http_status(:not_found)
    expect(units.last.reload.settings).not_to have_key(JrcContactCenter::CalendarCatalogState::KEY)
    expect(unit.reload.settings).not_to have_key(JrcContactCenter::CalendarCatalogState::KEY)
  end

  it 'does not resolve a foreign account unit in the authenticated current-account route' do
    other = create(:account)
    hidden = JrcContactCenter::Unit.create!(account: other, code: 'SYNTHETIC-HIDDEN', name: 'SYNTHETIC secret calendar unit', kind: 'sac')
    get base, headers: headers, params: { unit_id: hidden.id.to_s }
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(hidden.name)
    post base, headers: headers, params: body.merge(unit_id: hidden.id.to_s), as: :json
    expect(response).to have_http_status(:not_found)
    expect(hidden.reload.settings).not_to have_key(JrcContactCenter::CalendarCatalogState::KEY)
  end

  it 'reauthorizes a current profile and never treats administrator or recording rights as calendar configuration' do
    input = body
    member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_recordings_listen])
    get base, headers: headers, params: { unit_id: unit.id.to_s }
    expect(response).to have_http_status(:unauthorized)
    post base, headers: headers, params: input, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(unit.reload.settings).not_to have_key(JrcContactCenter::CalendarCatalogState::KEY)
  end

  it 'computes a saved explicit exception with the real native calculator without another write or a PABX command' do
    post base, headers: headers, params: body, as: :json
    expect(response).to have_http_status(:created)
    attributes = unit.reload.attributes
    audits = Audited.audit_class.count
    get "#{base}/#{entry.fetch('id')}/preview", headers: headers, params: { unit_id: unit.id.to_s, date: '2026-11-23' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('preview')).to include('precedence' => 'exception', 'working_seconds' => 3600, 'pabx_confirmed' => false)
    expect(unit.reload.attributes).to eq(attributes)
    expect(Audited.audit_class.count).to eq(audits)
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  it 'blocks reserved settings writes and hides the catalog from the unrelated generic unit payload' do
    post base, headers: headers, params: body, as: :json
    expect(response).to have_http_status(:created)
    endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/units/#{unit.id}"
    get endpoint, headers: headers
    expect(response.parsed_body.dig('item', 'settings')).not_to have_key(JrcContactCenter::CalendarCatalogState::KEY)
    patch endpoint, headers: headers, params: { unit: { settings: { JrcContactCenter::CalendarCatalogState::KEY => false } } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(unit.reload.settings.fetch(JrcContactCenter::CalendarCatalogState::KEY).fetch('entries')).to eq([entry])
  end

  it 'filters and counts before pagination and preserves the current native catalog when filters are removed' do
    context = { account: account, account_user: member, user: actor }
    service = JrcContactCenter::CalendarCatalog.new(context: context, unit_id: unit.id)
    21.times do |index|
      item = entry.deep_merge('id' => SecureRandom.uuid, 'active' => index.even?,
                              'definition' => { 'name' => format('SYNTHETIC page %02d', index) })
      service.save!(item, expected_revision: service.call.fetch('revision'), create: true)
    end
    get base, headers: headers, params: { unit_id: unit.id, q: 'SYNTHETIC page', page: 2, per_page: 20 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('meta')).to include('page' => 2, 'total' => 21, 'pages' => 2)
    expect(response.parsed_body.fetch('items').map { |row| row.dig('definition', 'name') }).to eq(['SYNTHETIC page 20'])
    get base, headers: headers, params: { unit_id: unit.id, status: 'active', page: 1, per_page: 5 }
    expect(response.parsed_body.fetch('meta')).to include('total' => 11, 'pages' => 3)
    expect(response.parsed_body.fetch('items').map { |row| row.fetch('active') }.uniq).to eq([true])
    get base, headers: headers, params: { unit_id: unit.id, page: 1, per_page: 100 }
    expect(response.parsed_body.fetch('items').size).to eq(21)
  end

  it 'rejects malformed filters and nonpositive pagination without silently selecting default rows' do
    [{ status: 'provider_applied' }, { page: '0' }, { page: '1.5' }, { per_page: '101' }, { q: ['SYNTHETIC'] }].each do |values|
      get base, headers: headers, params: values.merge(unit_id: unit.id)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.fetch('error')).to eq('invalid_contact_center_calendar_filter')
    end
    expect(unit.reload.settings).not_to have_key(JrcContactCenter::CalendarCatalogState::KEY)
  end

  {
    zero_version: ->(state) { state['version'] = 0 },
    foreign_scope: ->(state) { state.fetch('scope_snapshot')['account_id'] = '999999999999' },
    extra_header: ->(state) { state['authority'] = false },
    duplicate_identity: ->(state) { state.fetch('entries') << state.fetch('entries').first.deep_dup },
    string_active: ->(state) { state.fetch('entries').first['active'] = 'true' },
    too_many_entries: lambda do |state|
      source = state.fetch('entries').sole
      state['entries'] = Array.new(101) { source.deep_dup.merge('id' => SecureRandom.uuid) }
    end
  }.each do |name, change|
    it "preserves the stored catalog and its audit when an internal caller supplies #{name}" do
      post base, headers: headers, params: body, as: :json
      expect(response).to have_http_status(:created)
      stored = unit.reload.settings.deep_dup
      audits = Audited.audit_class.where(auditable: unit).count
      changed = stored.deep_dup
      change.call(changed.fetch(JrcContactCenter::CalendarCatalogState::KEY))
      expect(unit.update(settings: changed)).to be(false)
      expect(unit.reload.settings).to eq(stored)
      expect(Audited.audit_class.where(auditable: unit).count).to eq(audits)
    end
  end

  it 'does not remove or transfer a catalog silently when another internal caller changes the unit settings' do
    post base, headers: headers, params: body, as: :json
    expect(response).to have_http_status(:created)
    stored = unit.reload.settings.deep_dup
    expect(unit.update(settings: stored.except(JrcContactCenter::CalendarCatalogState::KEY))).to be(false)
    expect(unit.reload.settings).to eq(stored)
    changed_scope = stored.merge('business_unit_id' => business.last.id)
    expect(unit.update(settings: changed_scope)).to be(false)
    expect(unit.reload.settings).to eq(stored)
  end

  { overlapping: ->(row) { row.fetch('definition').fetch('weekly')['1'] = [['08:00', '12:00'], ['11:00', '17:00']] },
    false_holiday: ->(row) { row.fetch('definition')['holidays'] = [false] },
    authority: ->(row) { row.fetch('definition')['account_id'] = '999' } }.each do |name, mutate|
    it "rejects #{name} in the raw typed request instead of dropping it or saving a default" do
      input = body
      mutate.call(input.fetch(:calendar))
      post base, headers: headers, params: input, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(unit.reload.settings).not_to have_key(JrcContactCenter::CalendarCatalogState::KEY)
    end
  end
end
