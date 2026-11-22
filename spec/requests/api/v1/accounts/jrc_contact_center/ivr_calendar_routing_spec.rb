require 'rails_helper'

RSpec.describe 'Internal URA calendar branches use native scopes and exact attested snapshots', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, :contact_center_eligible, account: account) }
  let(:member) { account.account_users.find_by!(user: actor) }
  let!(:headers) { actor.create_new_auth_token }
  let(:company) { account.master_companies.create!(name: 'SYNTHETIC URA calendar issuer', relationship_type: 'internal') }
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
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center/ivr_drafts" }
  let(:entry) do
    { 'id' => SecureRandom.uuid, 'active' => true, 'definition' => {
      'name' => 'SYNTHETIC exact hours', 'description' => '', 'timezone' => 'America/Sao_Paulo',
      'weekly' => (1..7).to_h { |day| [day.to_s, day <= 5 ? [['08:00', '12:00'], ['13:00', '17:00']] : []] },
      'holidays' => [{ 'date' => '2026-11-23', 'name' => 'SYNTHETIC holiday', 'kind' => 'internal', 'type' => 'movable' },
                     { 'date' => '2026-11-26', 'name' => 'SYNTHETIC dated holiday', 'kind' => 'national', 'type' => 'fixed' }],
      'exceptions' => [{ 'date' => '2026-11-23', 'name' => 'SYNTHETIC duty', 'intervals' => [['10:00', '11:00']] },
                       { 'date' => '2026-11-24', 'name' => 'SYNTHETIC closure', 'intervals' => [] }]
    } }
  end
  let(:reference) do
    current = JrcContactCenter::CalendarCatalog.new(context: { account: account, account_user: member, user: actor }, unit_id: unit.id).call
    JrcContactCenter::IvrCalendarReferences.reference(entry, revision: current.fetch('revision'))
  end
  let(:definition) do
    { 'schema_version' => 3, 'start' => 'hours', 'nodes' => [
      { 'id' => 'hours', 'type' => 'calendar', 'calendar_reference' => reference, 'on_open' => 'open', 'on_closed' => 'closed' },
      { 'id' => 'open', 'type' => 'end' }, { 'id' => 'closed', 'type' => 'end' }
    ] }
  end
  let(:body) do
    { 'unit_id' => unit.id.to_s, 'name' => 'SYNTHETIC conditional URA', 'status' => 'draft', 'definition' => definition,
      'request_id' => SecureRandom.uuid, 'expected_revision' => 0 }
  end

  before do
    account.enable_features!('jrc_contact_center', 'audit_logs', 'custom_roles')
    member.update!(custom_role: create(:custom_role, account: account,
                                                     permissions: %w[jrc_contact_center_view jrc_contact_center_configure jrc_contact_center_audit]))
    account.jrc_crm_user_business_units.create!(user: actor, scope: 'BUSINESS_UNIT', company: company,
                                                business_unit: business.first, active: true, structure_managed: true)
    catalog = JrcContactCenter::CalendarCatalog.new(context: { account: account, account_user: member, user: actor }, unit_id: unit.id)
    catalog.save!(entry, expected_revision: catalog.call.fetch('revision'), create: true)
  end

  it 'offers the exact authorized catalog reference without changing configuration or claiming provider use' do
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/unit_calendars/#{entry.fetch('id')}", headers: headers,
                                                                                                 params: { unit_id: unit.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('ivr_reference')).to eq(reference)
    expect(response.parsed_body).to include('local_only' => true, 'pabx_confirmed' => false)
    expect(response.headers['Cache-Control']).to eq('no-store')
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  { '2026-11-23T12:59:59Z' => %w[closed exception], '2026-11-23T13:00:00Z' => %w[open exception],
    '2026-11-23T13:59:59Z' => %w[open exception], '2026-11-23T14:00:00Z' => %w[closed exception],
    '2026-11-23T10:00:00-03:00' => %w[open exception], '2026-11-24T16:00:00Z' => %w[closed exception],
    '2026-11-25T12:00:00Z' => %w[open weekly], '2026-11-26T12:00:00Z' => %w[closed holiday] }.each do |instant, expected|
    it "uses native date precedence and half-open boundaries at #{instant}" do
      post "#{base}/preview", headers: headers, params: { ivr_preview: {
        unit_id: unit.id.to_s, definition: definition, dtmf: '', at: instant
      } }, as: :json
      expect(response).to have_http_status(:ok)
      simulation = response.parsed_body.fetch('simulation')
      expect(simulation.fetch('trace').last.fetch('node_id')).to eq(expected.first)
      expect(simulation.fetch('trace').first.dig('calendar', 'precedence')).to eq(expected.last)
      expect(simulation.fetch('trace').first.dig('calendar', 'timezone')).to eq('America/Sao_Paulo')
      expect(simulation).to include('local_only' => true, 'provider_applied' => false, 'outcome' => 'ended')
      expect(JrcContactCenter::IvrDraftVersion.where(account: account)).to be_empty
      expect(JrcContactCenter::Command.where(account: account)).to be_empty
    end
  end

  [nil, false, [], {}, '', '2026-11-23T10:00:00', '2026-02-30T10:00:00Z', '2026-11-23T24:00:00Z'].each do |instant|
    it "does not invent a clock instant for #{instant.inspect}" do
      post "#{base}/preview", headers: headers, params: { ivr_preview: {
        unit_id: unit.id.to_s, definition: definition, dtmf: '', at: instant
      } }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.fetch('error')).to eq('ivr_calendar_instant_required')
      expect(JrcContactCenter::IvrDraftVersion.where(account: account)).to be_empty
    end
  end

  it 'persists the exact reviewed snapshot and its native audit source without a provider command' do
    post base, headers: headers, params: { ivr_draft: body }, as: :json
    expect(response).to have_http_status(:created)
    draft = JrcContactCenter::IvrDraft.find_by!(account: account, id: response.parsed_body.dig('item', 'id'))
    version = draft.latest_version
    expect(version.definition).to eq(definition)
    audit = Audited.audit_class.where(auditable: version, action: 'create').sole
    expect(audit.audited_changes.fetch('validated_calendar_references')).to include(
      hash_including('calendar_id' => reference.fetch('calendar_id'), 'unit_revision' => reference.fetch('unit_revision'),
                     'sha256' => reference.fetch('sha256'), 'source' => 'native_unit_catalog', 'unit_id' => unit.id.to_s)
    )
    expect(audit.audited_changes.dig('cc_scope', 'after')).to eq(draft.scope_snapshot)
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  it 'preserves attested history after a catalog edit while rejecting an unproven copy in a new draft' do
    original = body
    post base, headers: headers, params: { ivr_draft: original }, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.dig('item', 'id')
    draft = JrcContactCenter::IvrDraft.find_by!(account: account, id: id)
    previous = draft.latest_version.attributes.deep_dup
    catalog = JrcContactCenter::CalendarCatalog.new(context: { account: account, account_user: member, user: actor }, unit_id: unit.id)
    catalog.save!(entry.deep_merge('definition' => { 'name' => 'SYNTHETIC later catalog' }), expected_revision: catalog.call.fetch('revision'))
    post "#{base}/preview", headers: headers, params: { ivr_preview: {
      unit_id: unit.id.to_s, definition: definition, dtmf: '', at: '2026-11-23T13:00:00Z'
    } }, as: :json
    expect(response).to have_http_status(:conflict)
    post "#{base}/#{id}/simulate", headers: headers, params: { ivr_simulation: {
      revision: 1, dtmf: '', at: '2026-11-23T13:00:00Z'
    } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('simulation', 'trace').last.fetch('node_id')).to eq('open')
    patch "#{base}/#{id}", headers: headers, params: { ivr_draft: original.merge(
      'name' => 'SYNTHETIC revised other graph metadata', 'expected_revision' => 1, 'request_id' => SecureRandom.uuid
    ) }, as: :json
    expect(response).to have_http_status(:ok)
    expect(draft.versions.find_by!(revision: 1).attributes).to eq(previous)
    expect(draft.latest_version.definition).to eq(definition)
  end

  it 'does not use a bare model version as historical catalog attestation' do
    post base, headers: headers, params: { ivr_draft: body }, as: :json
    expect(response).to have_http_status(:created)
    draft = JrcContactCenter::IvrDraft.find_by!(account: account, id: response.parsed_body.dig('item', 'id'))
    audit = Audited.audit_class.where(auditable: draft.latest_version, action: 'create').sole
    audit.update!(audited_changes: audit.audited_changes.except('validated_calendar_references'))
    catalog = JrcContactCenter::CalendarCatalog.new(context: { account: account, account_user: member, user: actor }, unit_id: unit.id)
    catalog.save!(entry.deep_merge('definition' => { 'name' => 'SYNTHETIC changed source' }), expected_revision: catalog.call.fetch('revision'))
    post "#{base}/#{draft.id}/simulate", headers: headers, params: { ivr_simulation: {
      revision: 1, dtmf: '', at: '2026-11-23T13:00:00Z'
    } }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(draft.latest_version.definition).to eq(definition)
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  it 'cannot forge a valid content digest into authority to use a different snapshot' do
    changed = definition.deep_dup
    claim = changed.fetch('nodes').first.fetch('calendar_reference')
    claim.fetch('snapshot').fetch('definition')['name'] = 'SYNTHETIC unregistered claim'
    claim['sha256'] = JrcContactCenter::ConfigurationRevision.content_token(claim.fetch('snapshot'))
    post base, headers: headers, params: { ivr_draft: body.merge('definition' => changed) }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(JrcContactCenter::IvrDraftVersion.where(account: account)).to be_empty
    expect(JrcContactCenter::IvrDraft.where(account: account)).to be_empty
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  { 'on_open' => 'missing', 'on_closed' => 'missing' }.each do |field, value|
    it "rejects an absent #{field} destination instead of treating the calendar node as a terminal" do
      changed = definition.deep_dup
      changed.fetch('nodes').first[field] = value
      post base, headers: headers, params: { ivr_draft: body.merge('definition' => changed) }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.fetch('error')).to eq('ivr_missing_target')
      expect(JrcContactCenter::IvrDraftVersion.where(account: account)).to be_empty
    end
  end

  it 'rejects a closed calendar-only loop and preserves legacy schema1 and schema2 simulation contracts' do
    closed = definition.deep_dup
    closed.fetch('nodes').first.merge!('on_open' => 'hours', 'on_closed' => 'hours')
    post "#{base}/preview", headers: headers, params: { ivr_preview: { unit_id: unit.id.to_s, definition: closed, dtmf: '' } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('ivr_closed_loop')
    [1, 2].each do |schema|
      old = { 'schema_version' => schema, 'start' => 'done', 'nodes' => [{ 'id' => 'done', 'type' => 'end' }] }
      post "#{base}/preview", headers: headers, params: { ivr_preview: { unit_id: unit.id.to_s, definition: old, dtmf: '' } }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('simulation')).to include('outcome' => 'ended', 'local_only' => true, 'provider_applied' => false)
    end
  end

  it 'reauthorizes current profile and unit coverage before historical simulation or exact replay' do
    input = body
    post base, headers: headers, params: { ivr_draft: input }, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.dig('item', 'id')
    account.jrc_crm_user_business_units.where(user: actor).find_each { |row| row.update!(active: false) }
    post "#{base}/#{id}/simulate", headers: headers, params: { ivr_simulation: {
      revision: 1, dtmf: '', at: '2026-11-23T13:00:00Z'
    } }, as: :json
    expect(response).to have_http_status(:not_found)
    post base, headers: headers, params: { ivr_draft: input }, as: :json
    expect(response).to have_http_status(:not_found)
    member.custom_role.update!(permissions: %w[jrc_contact_center_view])
    post "#{base}/preview", headers: headers, params: { ivr_preview: {
      unit_id: unit.id.to_s, definition: definition, dtmf: '', at: '2026-11-23T13:00:00Z'
    } }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::IvrDraftVersion.where(account: account).count).to eq(1)
  end

  it 'accepts an explicit native local date, time and timezone without using the browser or server timezone' do
    post "#{base}/preview", headers: headers, params: { ivr_preview: {
      unit_id: unit.id.to_s, definition: definition, dtmf: '', at: { local: '2026-11-23T10:00', timezone: 'America/Sao_Paulo' }
    } }, as: :json
    expect(response).to have_http_status(:ok)
    trace = response.parsed_body.dig('simulation', 'trace')
    expect(trace.first.dig('calendar', 'instant')).to eq('2026-11-23T13:00:00Z')
    expect(trace.last.fetch('node_id')).to eq('open')
  end

  ['2026-03-29T02:30:00', '2026-10-25T02:30:00'].each do |local|
    it "rejects the non-unique named local instant #{local} instead of choosing a DST offset" do
      post "#{base}/preview", headers: headers, params: { ivr_preview: {
        unit_id: unit.id.to_s, definition: definition, dtmf: '', at: { local: local, timezone: 'Europe/Berlin' }
      } }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.fetch('error')).to eq('ivr_calendar_instant_required')
      expect(JrcContactCenter::Command.where(account: account)).to be_empty
    end
  end

  it 'does not turn a foreign account id into access to a reviewed calendar' do
    other = create(:account)
    post "/api/v1/accounts/#{other.id}/jrc_contact_center/ivr_drafts/preview", headers: headers, params: { ivr_preview: {
      unit_id: unit.id.to_s, definition: definition, dtmf: '', at: '2026-11-23T13:00:00Z'
    } }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::IvrDraftVersion.where(account: account)).to be_empty
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  it 'rejects a unit outside current corporate coverage even with a valid copied reference' do
    post "#{base}/preview", headers: headers, params: { ivr_preview: {
      unit_id: units.last.id.to_s, definition: definition, dtmf: '', at: '2026-11-23T13:00:00Z'
    } }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(JrcContactCenter::IvrDraftVersion.where(account: account)).to be_empty
  end

  [[], {}, false].each do |origin|
    it "rejects the malformed origin selector #{origin.inspect} instead of silently removing it" do
      post "#{base}/preview", headers: headers, params: { ivr_preview: {
        unit_id: unit.id.to_s, definition: definition, dtmf: '', at: '2026-11-23T13:00:00Z', origin_draft_id: origin
      } }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.fetch('error')).to eq('invalid_ivr_calendar_origin')
      expect(JrcContactCenter::IvrDraftVersion.where(account: account)).to be_empty
    end
  end

  it 'does not accept an extra scope claim inside the closed local-time input' do
    post "#{base}/preview", headers: headers, params: { ivr_preview: {
      unit_id: unit.id.to_s, definition: definition, dtmf: '',
      at: { local: '2026-11-23T10:00', timezone: 'America/Sao_Paulo', account_id: account.id }
    } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('ivr_calendar_instant_required')
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  it 'does not authorize a draft from another account as a historical calendar origin' do
    other = create(:account)
    other.enable_features!('jrc_contact_center', 'custom_roles')
    other_actor = create(:user, :contact_center_eligible, account: other)
    other_member = other.account_users.find_by!(user: other_actor)
    other_member.update!(custom_role: create(:custom_role, account: other, permissions: %w[jrc_contact_center_view jrc_contact_center_configure]))
    other_unit = JrcContactCenter::Unit.create!(account: other, code: 'SYNTHETIC', name: 'SYNTHETIC foreign unit', kind: 'sac')
    input = JrcContactCenter::IvrDraftInput.new(name: 'SYNTHETIC foreign draft', status: 'draft', expected_revision: 0,
                                                request_id: SecureRandom.uuid, definition: {
                                                  'schema_version' => 1, 'start' => 'done', 'nodes' => [{ 'id' => 'done', 'type' => 'end' }]
                                                })
    foreign = JrcContactCenter::IvrDraftWrite.new(context: { account: other, account_user: other_member, user: other_actor })
                                             .call(input: input, unit_id: other_unit.id).fetch(:draft)
    post "#{base}/preview", headers: headers, params: { ivr_preview: {
      unit_id: unit.id.to_s, definition: definition, dtmf: '', at: '2026-11-23T13:00:00Z', origin_draft_id: foreign.id.to_s
    } }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(JrcContactCenter::IvrDraftVersion.where(account: account)).to be_empty
    expect(foreign.latest_version.revision).to eq(1)
  end

  it 'replays the same authorized durable version after a catalog edit without creating a new version or command' do
    original = body
    post base, headers: headers, params: { ivr_draft: original }, as: :json
    expect(response).to have_http_status(:created)
    first = response.parsed_body.fetch('item')
    catalog = JrcContactCenter::CalendarCatalog.new(context: { account: account, account_user: member, user: actor }, unit_id: unit.id)
    catalog.save!(entry.deep_merge('definition' => { 'name' => 'SYNTHETIC changed after durable receipt' }),
                  expected_revision: catalog.call.fetch('revision'))
    post base, headers: headers, params: { ivr_draft: original }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('replayed' => true, 'latest_revision' => 1)
    expect(response.parsed_body.fetch('item')).to eq(first)
    expect(JrcContactCenter::IvrDraftVersion.where(account: account).count).to eq(1)
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  it 'keeps the frozen native version trigger effective for a schema3 calendar graph' do
    post base, headers: headers, params: { ivr_draft: body }, as: :json
    expect(response).to have_http_status(:created)
    version = JrcContactCenter::IvrDraft.find_by!(account: account, id: response.parsed_body.dig('item', 'id')).latest_version
    original = version.attributes.deep_dup
    connection = ActiveRecord::Base.connection
    sql = "UPDATE jrc_contact_center_ivr_draft_versions SET name = 'SYNTHETIC denied rewrite' WHERE id = #{connection.quote(version.id)}"
    expect do
      JrcContactCenter::IvrDraftVersion.transaction(requires_new: true) { connection.execute(sql) }
    end.to raise_error(ActiveRecord::StatementInvalid, /IVR revisions are immutable/)
    expect(version.reload.attributes).to eq(original)
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  it 'rejects ambiguous creation audits without replacing or mutating the historical version' do
    post base, headers: headers, params: { ivr_draft: body }, as: :json
    expect(response).to have_http_status(:created)
    draft = JrcContactCenter::IvrDraft.find_by!(account: account, id: response.parsed_body.dig('item', 'id'))
    version = draft.latest_version
    audit = Audited.audit_class.where(auditable: version, action: 'create').sole
    Audited.audit_class.create!(auditable: version, associated: account, user: actor, action: 'create',
                                comment: JrcContactCenter::ConfigurationAudit::COMMENT, audited_changes: audit.audited_changes.deep_dup)
    post "#{base}/#{draft.id}/simulate", headers: headers, params: { ivr_simulation: {
      revision: 1, dtmf: '', at: '2026-11-23T13:00:00Z'
    } }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('ivr_calendar_attestation_conflict')
    expect(version.reload.definition).to eq(definition)
    expect(draft.versions.count).to eq(1)
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end
end
