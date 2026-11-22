require 'rails_helper'

RSpec.describe 'Calendar usage inventory preserves current native URA heads and corporate permissions', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let(:headers) { actor.create_new_auth_token }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC calendar inventory company', relationship_type: 'internal') }
  let(:business) do
    %w[A B].map { |code| account.jrc_crm_business_units.create!(operating_company: company, code: code, name: "SYNTHETIC #{code}") }
  end
  let(:units) do
    business.map do |row|
      JrcContactCenter::Unit.create!(account: account, code: row.code, name: row.name, kind: 'sac',
                                     settings: { issuer_company_id: company.id, business_unit_id: row.id })
    end
  end
  let(:entry) do
    { 'id' => SecureRandom.uuid, 'active' => true, 'definition' => {
      'name' => 'SYNTHETIC inventory source', 'description' => '', 'timezone' => 'America/Sao_Paulo',
      'weekly' => (1..7).to_h { |day| [day.to_s, day == 1 ? [['08:00', '12:00']] : []] }, 'holidays' => [], 'exceptions' => []
    } }
  end
  let(:catalog) do
    JrcContactCenter::CalendarCatalog.new(context: { account: account, account_user: member, user: actor }, unit_id: units.first.id)
  end
  let(:definition) do
    reference = JrcContactCenter::IvrCalendarReferences.reference(entry, revision: catalog.call.fetch('revision'))
    { 'schema_version' => 3, 'start' => 'hours', 'nodes' => [
      { 'id' => 'hours', 'type' => 'calendar', 'calendar_reference' => reference, 'on_open' => 'done', 'on_closed' => 'done' },
      { 'id' => 'done', 'type' => 'end' }
    ] }
  end
  let(:writer) { JrcContactCenter::IvrDraftWrite.new(context: { account: account, account_user: member, user: actor }) }
  let(:values) do
    { name: 'SYNTHETIC current inventory draft', status: 'draft', definition: definition,
      expected_revision: 0, request_id: SecureRandom.uuid }
  end
  let(:draft) { writer.call(input: JrcContactCenter::IvrDraftInput.new(**values), unit_id: units.first.id).fetch(:draft) }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center/unit_calendars/#{entry.fetch('id')}/ivr_usages" }

  before do
    account.enable_features!('jrc_contact_center', 'custom_roles', 'audit_logs')
    member.update!(custom_role: create(:custom_role, account: account, permissions: %w[jrc_contact_center_view jrc_contact_center_configure]))
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: company,
                                                business_unit: business.first, active: true, structure_managed: true)
    catalog.save!(entry, expected_revision: catalog.call.fetch('revision'), create: true)
  end

  it 'returns an empty actual inventory without creating a default draft or claiming any provider use' do
    before = units.first.reload.settings.deep_dup
    get base, headers: headers, params: { unit_id: units.first.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include(
      'coverage' => 'current_local_ivr_drafts_only', 'provider_configuration_verified' => false,
      'local_only' => true, 'pabx_confirmed' => false, 'calendar_id' => entry.fetch('id'), 'items' => []
    )
    expect(response.parsed_body.fetch('meta')).to eq('page' => 1, 'per_page' => 10, 'total' => 0, 'pages' => 0)
    expect(response.headers['Cache-Control']).to eq('no-store')
    expect(JrcContactCenter::IvrDraftVersion.where(account: account)).to be_empty
    expect(units.first.reload.settings).to eq(before)
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  it 'does not resurrect an old pin after the current native draft head explicitly unlinks it' do
    current = draft
    original = current.latest_version.attributes.deep_dup
    unlinked = { 'schema_version' => 3, 'start' => 'done', 'nodes' => [{ 'id' => 'done', 'type' => 'end' }] }
    writer.call(input: JrcContactCenter::IvrDraftInput.new(**values, definition: unlinked, expected_revision: 1, request_id: SecureRandom.uuid),
                id: current.id)
    get base, headers: headers, params: { unit_id: units.first.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to eq([])
    expect(response.parsed_body.dig('meta', 'total')).to eq(0)
    expect(current.versions.find_by!(revision: 1).attributes).to eq(original)
    expect(current.latest_version.revision).to eq(2)
  end

  it 'counts one actual draft once and exposes both exact referenced nodes without returning its complete definition' do
    graph = definition.deep_dup
    second = graph.fetch('nodes').first.deep_dup.merge('id' => 'second_hours')
    graph.fetch('nodes').first['on_open'] = 'second_hours'
    graph.fetch('nodes') << second
    result = writer.call(input: JrcContactCenter::IvrDraftInput.new(**values, definition: graph), unit_id: units.first.id)
    get base, headers: headers, params: { unit_id: units.first.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('meta', 'total')).to eq(1)
    row = response.parsed_body.fetch('items').sole
    expect(row.fetch('draft_id')).to eq(result.fetch(:draft).id.to_s)
    expect(row.fetch('references').pluck('node_id')).to contain_exactly('hours', 'second_hours')
    expect(row.fetch('references').pluck('sha256').uniq).to eq([definition.fetch('nodes').first.dig('calendar_reference', 'sha256')])
    expect(row).not_to have_key('definition')
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  it 'applies native pagination after actual reference filtering across twenty-one persisted drafts' do
    ids = Array.new(21) do |index|
      input = JrcContactCenter::IvrDraftInput.new(**values, name: format('SYNTHETIC inventory %02d', index), request_id: SecureRandom.uuid)
      writer.call(input: input, unit_id: units.first.id).fetch(:draft).id.to_s
    end
    seen = []
    3.times do |index|
      get base, headers: headers, params: { unit_id: units.first.id, page: index + 1, per_page: 10 }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('meta')).to eq('page' => index + 1, 'per_page' => 10, 'total' => 21, 'pages' => 3)
      expect(response.parsed_body.fetch('items').length).to eq(index == 2 ? 1 : 10)
      seen.concat(response.parsed_body.fetch('items').pluck('draft_id'))
    end
    expect(seen).to eq(ids.reverse)
    expect(seen.uniq.length).to eq(21)
  end

  it 'compares each historical pin with the current catalog while preserving its immutable version and hash' do
    current = draft
    original = current.latest_version.attributes.deep_dup
    catalog.save!(entry.deep_merge('definition' => { 'name' => 'SYNTHETIC later source' }), expected_revision: catalog.call.fetch('revision'))
    get base, headers: headers, params: { unit_id: units.first.id }
    expect(response).to have_http_status(:ok)
    row = response.parsed_body.fetch('items').sole
    expect(row.fetch('references').sole).to include(
      'calendar_changed' => true, 'sha256' => definition.fetch('nodes').first.dig('calendar_reference', 'sha256')
    )
    expect(current.latest_version.attributes).to eq(original)
    expect(response.parsed_body.fetch('provider_configuration_verified')).to be(false)
  end

  it 'marks an archived native head explicitly and filters it without making it appear operational' do
    current = draft
    writer.call(input: JrcContactCenter::IvrDraftInput.new(**values, status: 'archived', expected_revision: 1, request_id: SecureRandom.uuid),
                id: current.id)
    get base, headers: headers, params: { unit_id: units.first.id, status: 'archived' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').sole).to include('status' => 'archived', 'local_only' => true, 'provider_applied' => false)
    get base, headers: headers, params: { unit_id: units.first.id, status: 'draft' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to eq([])
  end

  it 'treats SQL wildcard characters as literal bounded search text' do
    current = draft
    writer.call(input: JrcContactCenter::IvrDraftInput.new(**values, name: 'SYNTHETIC literal %_ marker', request_id: SecureRandom.uuid),
                unit_id: units.first.id)
    get base, headers: headers, params: { unit_id: units.first.id, q: '%_' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').pluck('name')).to eq(['SYNTHETIC literal %_ marker'])
    expect(current.latest_version.name).to eq(values.fetch(:name))
  end

  [{ page: 0 }, { page: [1] }, { per_page: 21 }, { q: [1] }, { q: 'x' * 101 }, { status: false }, { status: 'published' }].each do |filters|
    it "rejects malformed native filters #{filters.inspect} without broadening the inventory" do
      draft
      get base, headers: headers, params: { unit_id: units.first.id }.merge(filters)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.fetch('error')).to eq('invalid_contact_center_calendar_filter')
      expect(JrcContactCenter::Command.where(account: account)).to be_empty
    end
  end

  it 'denies another unit and another account instead of returning an empty authorized-looking list' do
    draft
    get base, headers: headers, params: { unit_id: units.last.id }
    expect(response).to have_http_status(:not_found)
    other = create(:account)
    get "/api/v1/accounts/#{other.id}/jrc_contact_center/unit_calendars/#{entry.fetch('id')}/ivr_usages",
        headers: headers, params: { unit_id: units.first.id }
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::IvrDraftVersion.where(account: account).count).to eq(1)
  end

  it 'refreshes configure permission and corporate coverage on every call to a reused native reader' do
    draft
    reader = JrcContactCenter::CalendarIvrUsages.new(
      context: { account: account, account_user: member, user: actor }, unit_id: units.first.id, calendar_id: entry.fetch('id')
    )
    expect(reader.call.fetch(:items).length).to eq(1)
    account.jrc_crm_user_business_units.where(user: actor).find_each { |row| row.update!(active: false) }
    expect { reader.call }.to raise_error(ActiveRecord::RecordNotFound)
    member.custom_role.update!(permissions: %w[jrc_contact_center_view])
    expect { reader.call }.to raise_error(Pundit::NotAuthorizedError)
    get base, headers: headers, params: { unit_id: units.first.id }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects ordinary catalog removal and scope relabeling without changing the native source or historical draft' do
    current = draft
    original = current.latest_version.attributes.deep_dup
    unit = units.first.reload
    settings = unit.settings.deep_dup
    other_company = account.master_companies.create!(name: 'SYNTHETIC guarded issuer', relationship_type: 'internal')
    other_business = account.jrc_crm_business_units.create!(operating_company: other_company, code: 'C', name: 'SYNTHETIC guarded scope')
    changed = settings.merge('issuer_company_id' => other_company.id, 'business_unit_id' => other_business.id)
    expect { unit.update!(settings: changed) }.to raise_error(ActiveRecord::RecordInvalid, /invalid_contact_center_calendar_catalog/)
    expect(unit.reload.settings).to eq(settings)
    expect do
      unit.update!(settings: settings.except(JrcContactCenter::CalendarCatalogState::KEY))
    end.to raise_error(ActiveRecord::RecordInvalid, /invalid_contact_center_calendar_catalog/)
    expect(unit.reload.settings).to eq(settings)
    expect(current.scope_snapshot.fetch('issuer_company_id')).to eq(company.id.to_s)
    expect(current.latest_version.attributes).to eq(original)
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  it 'intersects current unit visibility with the immutable historical issuer company' do
    current = draft
    original = current.latest_version.attributes.deep_dup
    next_company = account.master_companies.create!(name: 'SYNTHETIC other issuer', relationship_type: 'internal')
    next_business = account.jrc_crm_business_units.create!(operating_company: next_company, code: 'C', name: 'SYNTHETIC other scope')
    account.jrc_crm_user_business_units.where(user: actor).find_each { |row| row.update!(active: false) }
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: next_company,
                                                business_unit: next_business, active: true, structure_managed: true)
    # Adversarial synthetic SQL corruption of mutable unit/catalog metadata, not a supported reparenting operation.
    # The ordinary model guard is tested above and remains enabled. No database trigger is disabled here.
    unit = units.first.reload
    unit.settings = unit.settings.merge('issuer_company_id' => next_company.id, 'business_unit_id' => next_business.id)
    key = JrcContactCenter::CalendarCatalogState::KEY
    unit.settings[key]['scope_snapshot'] = JrcContactCenter::CalendarCatalogState.new(unit: unit).scope
    connection = JrcContactCenter::Unit.connection
    sql = <<~SQL.squish
      UPDATE jrc_contact_center_units SET settings = #{connection.quote(unit.settings.to_json)}::jsonb
      WHERE account_id = #{account.id} AND id = #{unit.id}
    SQL
    connection.execute(sql)
    scopes = [JrcContactCenter::CalendarCatalogState.new(unit: unit.reload).call.fetch('scope_snapshot').fetch('issuer_company_id'),
              current.scope_snapshot.fetch('issuer_company_id')]
    expect(scopes).to eq([next_company.id.to_s, company.id.to_s])
    get base, headers: headers, params: { unit_id: unit.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to eq([])
    expect(response.parsed_body.dig('meta', 'total')).to eq(0)
    expect(current.latest_version.attributes).to eq(original)
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/ivr_drafts/#{current.id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end
end
