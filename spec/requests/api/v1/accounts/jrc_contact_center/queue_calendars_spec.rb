require 'rails_helper'

RSpec.describe 'Call Center queue calendar drafts pin reviewed snapshots without provider application', type: :request do
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
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center/queue_calendars" }
  let(:definition) do
    { 'name' => 'SYNTHETIC internal schedule', 'description' => '', 'timezone' => 'America/Sao_Paulo',
      'weekly' => (1..7).to_h { |day| [day.to_s, day <= 5 ? [['08:00', '12:00'], ['13:00', '17:00']] : []] },
      'holidays' => [{ 'date' => '2026-11-23', 'name' => 'SYNTHETIC holiday', 'kind' => 'internal', 'type' => 'movable' }],
      'exceptions' => [{ 'date' => '2026-11-23', 'name' => 'SYNTHETIC duty', 'intervals' => [['10:00', '11:00']] }] }
  end
  let(:entry) { { 'id' => SecureRandom.uuid, 'active' => true, 'definition' => definition } }
  let(:queue) { JrcContactCenter::Queue.create!(account: account, unit: unit, code: 'SYNTHETIC-Q', name: 'SYNTHETIC queue') }
  let(:body) do
    { 'unit_id' => unit.id.to_s, 'queue_id' => queue.id.to_s, 'calendar_id' => entry.fetch('id'),
      'calendar_revision' => JrcContactCenter::ConfigurationRevision.token(unit.reload),
      'queue_revision' => JrcContactCenter::ConfigurationRevision.token(queue.reload), 'idempotency_key' => SecureRandom.uuid, 'reviewed' => true }
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

  it 'reads an empty current queue association without creating a default or a provider command' do
    get "#{base}/#{queue.id}", headers: headers, params: { unit_id: unit.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('binding' => nil, 'local_only' => true, 'pabx_confirmed' => false, 'external_impact' => 'unknown')
    expect(response.headers['Cache-Control']).to eq('no-store')
    expect(queue.reload.settings).not_to have_key(JrcContactCenter::QueueCalendarState::KEY)
  end

  it 'pins the exact authorized snapshot and native scope and audits its real persisted association' do
    input = body
    patch "#{base}/#{queue.id}", headers: headers, params: input, as: :json
    expect(response).to have_http_status(:ok)
    value = response.parsed_body.fetch('binding')
    expect(value).to include('id' => input.fetch('idempotency_key'), 'calendar_snapshot' => entry)
    expect(value.fetch('scope_snapshot')).to include('account_id' => account.id.to_s, 'unit_id' => unit.id.to_s, 'queue_id' => queue.id.to_s)
    expect(queue.reload.settings.fetch(JrcContactCenter::QueueCalendarState::KEY)).to eq(value)
    audit = Audited.audit_class.where(auditable: queue, action: 'update').last!
    expect(audit.audited_changes.dig('attributes', 1, 'settings', JrcContactCenter::QueueCalendarState::KEY)).to eq(value)
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  it 'recovers the same reviewed request without another mutation or audit despite the old revision tokens' do
    input = body
    patch "#{base}/#{queue.id}", headers: headers, params: input, as: :json
    expected = response.parsed_body
    audits = Audited.audit_class.where(auditable: queue).count
    patch "#{base}/#{queue.id}", headers: headers, params: input, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(expected)
    expect(Audited.audit_class.where(auditable: queue).count).to eq(audits)
  end

  it 'rejects reuse of the same request identity for a different reviewed body' do
    input = body
    patch "#{base}/#{queue.id}", headers: headers, params: input, as: :json
    stored = queue.reload.settings.deep_dup
    patch "#{base}/#{queue.id}", headers: headers, params: input.merge('calendar_revision' => 'f' * 64), as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('queue_calendar_identity_conflict')
    expect(queue.reload.settings).to eq(stored)
  end

  it 'keeps the pinned configuration when its catalog source changes and reports the real divergence' do
    patch "#{base}/#{queue.id}", headers: headers, params: body, as: :json
    stored = response.parsed_body.fetch('binding')
    catalog = JrcContactCenter::CalendarCatalog.new(context: { account: account, account_user: member, user: actor }, unit_id: unit.id)
    changed = entry.deep_merge('definition' => { 'name' => 'SYNTHETIC later calendar' })
    catalog.save!(changed, expected_revision: catalog.call.fetch('revision'))
    get "#{base}/#{queue.id}", headers: headers, params: { unit_id: unit.id }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('binding' => stored, 'calendar_changed' => true, 'pabx_confirmed' => false)
    expect(queue.reload.settings.fetch(JrcContactCenter::QueueCalendarState::KEY)).to eq(stored)
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  %w[calendar_revision queue_revision].each do |field|
    it "rejects a stale #{field} without a write or audit" do
      input = body.merge(field => 'f' * 64)
      stored = queue.reload.attributes
      audits = Audited.audit_class.count
      patch "#{base}/#{queue.id}", headers: headers, params: input, as: :json
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body.fetch('error')).to eq('stale_configuration_revision')
      expect(queue.reload.attributes).to eq(stored)
      expect(Audited.audit_class.count).to eq(audits)
    end
  end

  it 'does not use the body or route identifiers to confer access to another native unit' do
    hidden = JrcContactCenter::Queue.create!(account: account, unit: units.last, code: 'SYNTHETIC-HIDDEN', name: 'SYNTHETIC hidden')
    input = body.merge('queue_id' => hidden.id.to_s, 'unit_id' => units.last.id.to_s)
    get "#{base}/#{hidden.id}", headers: headers, params: { unit_id: units.last.id }
    expect(response).to have_http_status(:not_found)
    patch "#{base}/#{hidden.id}", headers: headers, params: input, as: :json
    expect(response).to have_http_status(:not_found)
    expect(hidden.reload.settings).not_to have_key(JrcContactCenter::QueueCalendarState::KEY)
  end

  it 'does not resolve a foreign account queue even when its numeric ID is known' do
    other = create(:account)
    foreign_unit = JrcContactCenter::Unit.create!(account: other, code: 'SYNTHETIC-F', name: 'SYNTHETIC foreign', kind: 'sac')
    hidden = JrcContactCenter::Queue.create!(account: other, unit: foreign_unit, code: 'SYNTHETIC-FQ', name: 'SYNTHETIC foreign queue')
    get "#{base}/#{hidden.id}", headers: headers, params: { unit_id: unit.id }
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(hidden.name)
    patch "#{base}/#{hidden.id}", headers: headers, params: body.merge('queue_id' => hidden.id.to_s), as: :json
    expect(response).to have_http_status(:not_found)
    expect(hidden.reload.settings).not_to have_key(JrcContactCenter::QueueCalendarState::KEY)
  end

  it 'reauthorizes replay and reads after a profile loses configuration authority' do
    input = body
    patch "#{base}/#{queue.id}", headers: headers, params: input, as: :json
    stored = queue.reload.attributes
    member.custom_role.update!(permissions: %w[jrc_contact_center_view])
    get "#{base}/#{queue.id}", headers: headers, params: { unit_id: unit.id }
    expect(response).to have_http_status(:unauthorized)
    patch "#{base}/#{queue.id}", headers: headers, params: input, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(queue.reload.attributes).to eq(stored)
  end

  { review_false: { 'reviewed' => false }, extra_authority: { 'account_id' => '999' },
    invalid_key: { 'idempotency_key' => 'not-a-uuid' }, queue_route_mismatch: { 'queue_id' => '999999999' } }.each do |name, values|
    it "rejects #{name} in the raw typed request without granting access or creating an association" do
      patch "#{base}/#{queue.id}", headers: headers, params: body.merge(values), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(queue.reload.settings).not_to have_key(JrcContactCenter::QueueCalendarState::KEY)
    end
  end

  it 'cannot overwrite the reserved association through generic queue settings and keeps legacy replacement semantics' do
    patch "#{base}/#{queue.id}", headers: headers, params: body, as: :json
    stored = queue.reload.settings.fetch(JrcContactCenter::QueueCalendarState::KEY)
    endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/queues/#{queue.id}"
    get endpoint, headers: headers
    expect(response.parsed_body.dig('item', 'settings')).not_to have_key(JrcContactCenter::QueueCalendarState::KEY)
    patch endpoint, headers: headers, params: { queue: { settings: { JrcContactCenter::QueueCalendarState::KEY => false } } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    patch endpoint, headers: headers, params: { queue: { settings: { 'legacy' => true } } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(queue.reload.settings).to eq('legacy' => true, JrcContactCenter::QueueCalendarState::KEY => stored)
    patch endpoint, headers: headers, params: { queue: { settings: {} } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(queue.reload.settings).to eq(JrcContactCenter::QueueCalendarState::KEY => stored)
  end

  it 'does not silently discard or transfer the association through an internal model caller' do
    patch "#{base}/#{queue.id}", headers: headers, params: body, as: :json
    stored = queue.reload.settings.deep_dup
    expect(queue.update(settings: {})).to be(false)
    expect(queue.reload.settings).to eq(stored)
    expect(queue.update(unit: units.last)).to be(false)
    expect(queue.reload.unit_id).to eq(unit.id)
  end

  { format: ->(value) { value['format'] = 'unknown' },
    scope: ->(value) { value.fetch('scope_snapshot')['account_id'] = '999999' },
    digest: ->(value) { value['calendar_digest'] = 'f' * 64 },
    snapshot: ->(value) { value.fetch('calendar_snapshot')['active'] = 'true' },
    extra: ->(value) { value['permission'] = true } }.each do |name, mutate|
    it "retains stored data and audit when a model caller supplies malformed #{name}" do
      patch "#{base}/#{queue.id}", headers: headers, params: body, as: :json
      stored = queue.reload.settings.deep_dup
      audits = Audited.audit_class.where(auditable: queue).count
      changed = stored.deep_dup
      mutate.call(changed.fetch(JrcContactCenter::QueueCalendarState::KEY))
      expect(queue.update(settings: changed)).to be(false)
      expect(queue.reload.settings).to eq(stored)
      expect(Audited.audit_class.where(auditable: queue).count).to eq(audits)
    end
  end

  it 'uses canonical snapshot content so JSONB key ordering cannot create a false change or alter existing record tokens' do
    value = { 'b' => { 'y' => false, 'x' => 1 }, 'a' => [2, 3] }
    other = { 'a' => [2, 3], 'b' => { 'x' => 1, 'y' => false } }
    expect(JrcContactCenter::ConfigurationRevision.content_token(value)).to eq(JrcContactCenter::ConfigurationRevision.content_token(other))
    before = JrcContactCenter::ConfigurationRevision.token(queue)
    expect(JrcContactCenter::ConfigurationRevision.token(queue.reload)).to eq(before)
    expect(JrcContactCenter::ConfigurationRevision.content_token(value)).not_to eq(
      JrcContactCenter::ConfigurationRevision.content_token(other.merge('a' => [3, 2]))
    )
  end

  it 'counts authorized native queues before pagination and returns search results without implying a provider link' do
    21.times do |index|
      JrcContactCenter::Queue.create!(account: account, unit: unit, code: "SYNTHETIC-#{index}", name: format('SYNTHETIC queue %02d', index))
    end
    get base, headers: headers, params: { unit_id: unit.id, calendar_id: entry.fetch('id'), page: 2, per_page: 20 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('meta')).to include('total' => 21, 'page' => 2, 'pages' => 2)
    expect(response.parsed_body.fetch('items').sole).to include('queue_name' => 'SYNTHETIC queue 20', 'binding' => nil,
                                                                 'external_impact' => 'unknown', 'pabx_confirmed' => false)
    get base, headers: headers, params: { unit_id: unit.id, calendar_id: entry.fetch('id'), q: 'queue 03', page: 1 }
    expect(response.parsed_body.fetch('meta')).to include('total' => 1, 'pages' => 1)
  end
end
