require 'rails_helper'

RSpec.describe 'Explicit reviewed internal queue calendar removal and durable historical receipts', type: :request do
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

  let(:removal) do
    { 'unit_id' => unit.id.to_s, 'queue_id' => queue.id.to_s,
      'binding_id' => queue.reload.settings.fetch(JrcContactCenter::QueueCalendarState::KEY).fetch('id'),
      'expected_revision' => JrcContactCenter::ConfigurationRevision.token(queue), 'idempotency_key' => SecureRandom.uuid, 'reviewed' => true }
  end

  before do
    patch "#{base}/#{queue.id}", headers: headers, params: body, as: :json
    expect(response).to have_http_status(:ok)
  end

  it 'removes only the reviewed internal association and preserves the pinned snapshot in native history' do
    old = queue.reload.settings.fetch(JrcContactCenter::QueueCalendarState::KEY)
    audits = Audited.audit_class.where(auditable: queue).count
    delete "#{base}/#{queue.id}", headers: headers, params: removal, as: :json
    expect(response).to have_http_status(:ok)
    receipt = response.parsed_body
    expect(receipt).to include('removed_binding_id' => old.fetch('id'), 'historical_receipt' => true,
                               'local_only' => true, 'pabx_confirmed' => false, 'external_impact' => 'unknown')
    expect(queue.reload.settings).not_to have_key(JrcContactCenter::QueueCalendarState::KEY)
    expect(Audited.audit_class.where(auditable: queue).count).to eq(audits + 1)
    audit = Audited.audit_class.find(receipt.fetch('audit_id'))
    expect(audit.audited_changes.dig('queue_calendar_removal', 'reviewed')).to be(true)
    expect(audit.audited_changes.dig('attributes', 0, 'settings', JrcContactCenter::QueueCalendarState::KEY)).to eq(old)
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  it 'recovers exactly the same committed removal receipt without a second audit or another write' do
    input = removal
    delete "#{base}/#{queue.id}", headers: headers, params: input, as: :json
    expect(response).to have_http_status(:ok)
    first = response.parsed_body
    stored = queue.reload.attributes
    audits = Audited.audit_class.where(auditable: queue).count
    delete "#{base}/#{queue.id}", headers: headers, params: input, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(first)
    expect(queue.reload.attributes).to eq(stored)
    expect(Audited.audit_class.where(auditable: queue).count).to eq(audits)
  end

  it 'never removes a newer association when the old removal request is replayed' do
    input = removal
    delete "#{base}/#{queue.id}", headers: headers, params: input, as: :json
    expect(response).to have_http_status(:ok)
    first = response.parsed_body
    binding = body.merge('queue_revision' => JrcContactCenter::ConfigurationRevision.token(queue.reload),
                          'idempotency_key' => SecureRandom.uuid)
    patch "#{base}/#{queue.id}", headers: headers, params: binding, as: :json
    expect(response).to have_http_status(:ok)
    newer = response.parsed_body.fetch('binding')
    audits = Audited.audit_class.where(auditable: queue).count
    delete "#{base}/#{queue.id}", headers: headers, params: input, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(first)
    expect(queue.reload.settings.fetch(JrcContactCenter::QueueCalendarState::KEY)).to eq(newer)
    expect(Audited.audit_class.where(auditable: queue).count).to eq(audits)
  end

  it 'does not infer successful removal from absence of a binding without the exact durable request receipt' do
    input = removal
    delete "#{base}/#{queue.id}", headers: headers, params: input, as: :json
    expect(response).to have_http_status(:ok)
    audits = Audited.audit_class.where(auditable: queue).count
    delete "#{base}/#{queue.id}", headers: headers, params: input.merge('idempotency_key' => SecureRandom.uuid), as: :json
    expect(response).to have_http_status(:conflict)
    expect(Audited.audit_class.where(auditable: queue).count).to eq(audits)
  end

  it 'denies removal and receipt recovery after the current profile loses configuration authority' do
    input = removal
    delete "#{base}/#{queue.id}", headers: headers, params: input, as: :json
    expect(response).to have_http_status(:ok)
    stored = queue.reload.attributes
    member.custom_role.update!(permissions: ['jrc_contact_center_view'])
    delete "#{base}/#{queue.id}", headers: headers, params: input, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(queue.reload.attributes).to eq(stored)
  end

  it 'does not accept the transient native intent through generic queue attributes or reserved settings' do
    stored = queue.reload.attributes
    endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/queues/#{queue.id}"
    patch endpoint, headers: headers, params: { queue: { settings: {}, cc_calendar_removal_review: removal } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(queue.reload.settings).to eq(stored.fetch('settings'))
    patch endpoint, headers: headers, params: { queue: { settings: { JrcContactCenter::QueueCalendarState::KEY => nil } } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(queue.reload.settings).to eq(stored.fetch('settings'))
  end

  %w[expected_revision binding_id].each do |field|
    it "rejects stale #{field} while preserving the association and audit history" do
      input = removal.merge(field => field == 'binding_id' ? SecureRandom.uuid : 'f' * 64)
      stored = queue.reload.attributes
      audits = Audited.audit_class.count
      delete "#{base}/#{queue.id}", headers: headers, params: input, as: :json
      expect(response).to have_http_status(:conflict)
      expect(queue.reload.attributes).to eq(stored)
      expect(Audited.audit_class.count).to eq(audits)
    end
  end

  [false, [], nil, { 'reviewed' => false }, { 'unit_id' => '0' }, { 'queue_id' => '020' },
   { 'expected_revision' => nil }, { 'expected_revision' => false }, { 'grant' => 'configure' },
   { 'unit_id' => false }, { 'unit_id' => [] }, { 'unit_id' => {} },
   { 'idempotency_key' => 'bad' }].each do |changes|
    it "rejects malformed explicit removal input #{changes.inspect} without mutating the native association" do
      input = changes.is_a?(Hash) ? removal.merge(changes) : changes
      stored = queue.reload.attributes
      audits = Audited.audit_class.count
      delete "#{base}/#{queue.id}", params: input.to_json, headers: headers.merge('CONTENT_TYPE' => 'application/json')
      expect(response).to have_http_status(:unprocessable_entity)
      expect(queue.reload.attributes).to eq(stored)
      expect(Audited.audit_class.count).to eq(audits)
    end
  end

  %w[unit_id queue_id expected_revision binding_id idempotency_key reviewed].each do |field|
    it "rejects missing #{field} without changing the association" do
      input = removal.except(field)
      stored = queue.reload.attributes
      delete "#{base}/#{queue.id}", headers: headers, params: input, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(queue.reload.attributes).to eq(stored)
    end
  end

  it 'rejects route and body queue identity disagreement without touching either queue' do
    stored = queue.reload.attributes
    delete "#{base}/#{queue.id}", headers: headers, params: removal.merge('queue_id' => (queue.id + 1).to_s), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(queue.reload.attributes).to eq(stored)
  end

  it 'does not grant removal from a unit identifier outside current corporate coverage' do
    stored = queue.reload.attributes
    delete "#{base}/#{queue.id}", headers: headers, params: removal.merge('unit_id' => units.last.id.to_s), as: :json
    expect(response).to have_http_status(:not_found)
    expect(queue.reload.attributes).to eq(stored)
  end

  it 'does not discover a foreign queue even when its ID is supplied by an authorized operator' do
    other = create(:account)
    foreign_unit = JrcContactCenter::Unit.create!(account: other, code: 'SYNTHETIC-F', name: 'SYNTHETIC foreign', kind: 'sac')
    hidden = JrcContactCenter::Queue.create!(account: other, unit: foreign_unit, code: 'SYNTHETIC-FQ', name: 'SYNTHETIC foreign queue')
    stored = queue.reload.attributes
    delete "#{base}/#{hidden.id}", headers: headers, params: removal.merge('queue_id' => hidden.id.to_s), as: :json
    expect(response).to have_http_status(:not_found)
    expect(queue.reload.attributes).to eq(stored)
    expect(response.body).not_to include(hidden.name)
  end

  it 'never recovers a nonce reused with a changed reviewed request, despite successful prior removal' do
    input = removal
    delete "#{base}/#{queue.id}", headers: headers, params: input, as: :json
    expect(response).to have_http_status(:ok)
    stored = queue.reload.attributes
    delete "#{base}/#{queue.id}", headers: headers, params: input.merge('expected_revision' => 'f' * 64), as: :json
    expect(response).to have_http_status(:conflict)
    expect(queue.reload.attributes).to eq(stored)
  end

  it 'rolls back the actual queue change when its mandatory native audit write fails' do
    input = removal
    stored = queue.reload.attributes
    audits = Audited.audit_class.count
    allow(Audited.audit_class).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(Audited.audit_class.new))
    service = JrcContactCenter::QueueCalendarRemovals.new(context: { account: account, account_user: member, user: actor }, unit_id: unit.id)
    Current.set(user: actor) do
      expect { service.call(input) }.to raise_error(ActiveRecord::RecordInvalid)
    end
    expect(queue.reload.attributes).to eq(stored)
    expect(Audited.audit_class.count).to eq(audits)
  end

  it 'rolls back removal if the audit callback is silenced and no durable receipt can be recovered' do
    input = removal
    stored = queue.reload.attributes
    audits = Audited.audit_class.count
    allow(JrcContactCenter::ConfigurationAudit).to receive(:write!)
    delete "#{base}/#{queue.id}", headers: headers, params: input, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('queue_calendar_removal_receipt_missing')
    expect(queue.reload.attributes).to eq(stored)
    expect(Audited.audit_class.count).to eq(audits)
  end

  it 'rejects ambiguous duplicate historical receipts instead of guessing which operation committed' do
    input = removal
    delete "#{base}/#{queue.id}", headers: headers, params: input, as: :json
    expect(response).to have_http_status(:ok)
    audit = Audited.audit_class.find(response.parsed_body.fetch('audit_id'))
    audit.dup.save!
    stored = queue.reload.attributes
    delete "#{base}/#{queue.id}", headers: headers, params: input, as: :json
    expect(response).to have_http_status(:conflict)
    expect(queue.reload.attributes).to eq(stored)
  end

  it 'preserves all unrelated native queue settings when removing the reserved calendar association' do
    queue.update!(settings: queue.reload.settings.merge('legacy_internal_mode' => { 'name' => 'SYNTHETIC preserved' }))
    input = removal
    expected = queue.settings.except(JrcContactCenter::QueueCalendarState::KEY)
    delete "#{base}/#{queue.id}", headers: headers, params: input, as: :json
    expect(response).to have_http_status(:ok)
    expect(queue.reload.settings).to eq(expected)
    expect(queue.settings.fetch('legacy_internal_mode')).to eq('name' => 'SYNTHETIC preserved')
  end

  it 'does not expose another actor receipt even when both actors currently configure the same unit' do
    input = removal
    delete "#{base}/#{queue.id}", headers: headers, params: input, as: :json
    expect(response).to have_http_status(:ok)
    other = create(:user, :contact_center_eligible, account: account)
    account.account_users.find_by!(user: other).update!(custom_role: member.custom_role)
    account.jrc_crm_user_business_units.create!(user: other, scope: 'BUSINESS_UNIT', company: company,
                                               business_unit: business.first, active: true, structure_managed: true)
    stored = queue.reload.attributes
    audits = Audited.audit_class.count
    delete "#{base}/#{queue.id}", headers: other.create_new_auth_token, params: input, as: :json
    expect(response).to have_http_status(:conflict)
    expect(queue.reload.attributes).to eq(stored)
    expect(Audited.audit_class.count).to eq(audits)
  end

  it 'does not recover a historical receipt after current native company and unit coverage is withdrawn' do
    input = removal
    delete "#{base}/#{queue.id}", headers: headers, params: input, as: :json
    expect(response).to have_http_status(:ok)
    account.jrc_crm_user_business_units.where(user: actor).find_each { |row| row.update!(active: false) }
    stored = queue.reload.attributes
    delete "#{base}/#{queue.id}", headers: headers, params: input, as: :json
    expect(response).to have_http_status(:not_found)
    expect(queue.reload.attributes).to eq(stored)
  end
end
