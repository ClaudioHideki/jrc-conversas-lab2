require 'rails_helper'

RSpec.describe 'Call Center local IVR draft API', type: :request do
  let(:account) { create(:account) }
  let(:operator) { create(:user, :contact_center_eligible, account: account, role: :administrator) }
  let(:member) { account.account_users.find_by!(user: operator) }
  let(:headers) { operator.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/jrc_contact_center/ivr_drafts" }
  let(:unit) { JrcContactCenter::Unit.create!(account: account, code: 'LOCAL', name: 'SYNTHETIC unit', kind: 'sac') }
  let(:definition) { { schema_version: 1, start: 'end', nodes: [{ id: 'end', type: 'end' }] } }
  let(:values) do
    { unit_id: unit.id, name: 'SYNTHETIC draft', status: 'draft', definition: definition,
      request_id: SecureRandom.uuid, expected_revision: 0 }
  end
  let(:initial) do
    post url, headers: headers, params: { ivr_draft: values }, as: :json
    response.parsed_body.fetch('item')
  end

  before { account.enable_features!('jrc_contact_center') }

  it 'returns creation status for a new durable local identity' do
    initial
    expect(response).to have_http_status(:created)
  end

  it 'persists a local revision and reloads it through authenticated real APIs' do
    original = initial
    get "#{url}/#{original.fetch('id')}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item')).to eq(original)
    expect(original).to include('revision' => 1, 'local_only' => true, 'provider_applied' => false)
    expect(original.fetch('definition')).to eq(JSON.parse(definition.to_json))
    expect(response.headers['Cache-Control']).to eq('no-store')
    expect(response.body).not_to include(operator.email, 'access-token')
  end

  it 'requires a precondition and never assumes the currently stored revision' do
    post url, headers: headers, params: { ivr_draft: values.except(:expected_revision) }, as: :json
    expect(response).to have_http_status(:precondition_required)
    expect(response.parsed_body).to include('error' => 'ivr_revision_required')
    expect(JrcContactCenter::IvrDraft.where(account: account)).to be_empty
  end

  %i[name status definition request_id].each do |field|
    it "rejects missing #{field} as a request error without creating an identity" do
      post url, headers: headers, params: { ivr_draft: values.except(field) }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JrcContactCenter::IvrDraft.where(account: account)).to be_empty
    end
  end

  it 'keeps an accepted revision when invalid JSON or a closed cycle is submitted' do
    original = initial
    menu = { id: 'entry', type: 'menu', timeout_seconds: 5, max_attempts: 2,
             options: [{ digit: '1', target: 'entry' }], on_timeout: 'entry', on_invalid: 'entry' }
    malformed = { schema_version: 1, start: 'entry', nodes: [menu] }
    [nil, malformed].each do |graph|
      patch "#{url}/#{original['id']}", headers: headers,
                                        params: { ivr_draft: values.merge(definition: graph, expected_revision: 1, request_id: SecureRandom.uuid) },
                                        as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    get "#{url}/#{original['id']}", headers: headers
    expect(response.parsed_body.fetch('item')).to eq(original)
  end

  it 'returns an explicit conflict and preserves both the accepted head and immutable history' do
    original = initial
    update = values.merge(expected_revision: 1, request_id: SecureRandom.uuid, name: 'SYNTHETIC accepted')
    patch "#{url}/#{original['id']}", headers: headers, params: { ivr_draft: update }, as: :json
    expect(response).to have_http_status(:ok)
    stale = update.merge(request_id: SecureRandom.uuid, name: 'SYNTHETIC stale')
    patch "#{url}/#{original['id']}", headers: headers, params: { ivr_draft: stale }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body).to include('error' => 'stale_ivr_revision')
    get "#{url}/#{original['id']}/versions/1", headers: headers
    expect(response.parsed_body.fetch('item')).to eq(original)
    get "#{url}/#{original['id']}", headers: headers
    expect(response.parsed_body.fetch('item')).to include('name' => 'SYNTHETIC accepted', 'revision' => 2)
  end

  it 'replays the same request without a second revision or misleading creation status' do
    original = initial
    post url, headers: headers, params: { ivr_draft: values }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('replayed' => true, 'latest_revision' => 1)
    expect(response.parsed_body.fetch('item')).to eq(original)
    expect(JrcContactCenter::IvrDraftVersion.where(account: account).count).to eq(1)
  end

  it 'never changes a draft unit through update parameters' do
    original = initial
    other = JrcContactCenter::Unit.create!(account: account, code: 'OTHER', name: 'SYNTHETIC other', kind: 'sac')
    patch "#{url}/#{original['id']}", headers: headers,
                                      params: { ivr_draft: values.merge(unit_id: other.id, expected_revision: 1, request_id: SecureRandom.uuid) },
                                      as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('error' => 'ivr_unit_is_immutable')
    expect(JrcContactCenter::IvrDraft.find(original['id']).unit_id).to eq(unit.id)
  end

  it 'always paginates lists, omits graph payloads and preserves disjoint pages and filters' do
    context = { account: account, account_user: member, user: operator }
    writer = JrcContactCenter::IvrDraftWrite.new(context: context)
    23.times do |index|
      input = JrcContactCenter::IvrDraftInput.new(**values.except(:unit_id), definition: JSON.parse(definition.to_json),
                                                                             name: "SYNTHETIC page #{index}", request_id: SecureRandom.uuid)
      writer.call(input: input, unit_id: unit.id)
    end
    get url, headers: headers
    first = response.parsed_body
    expect(first.fetch('meta')).to include('page' => 1, 'per_page' => 20, 'total' => 23, 'pages' => 2)
    expect(first.fetch('items').length).to eq(20)
    expect(first.fetch('items').first).not_to have_key('definition')
    get url, headers: headers, params: { page: 2 }
    last = response.parsed_body.fetch('items')
    expect(last.length).to eq(3)
    expect(first.fetch('items').pluck('id') & last.pluck('id')).to be_empty
    get url, headers: headers, params: { q: 'page 22', unit_id: unit.id, status: 'draft', per_page: 1000 }
    expect(response.parsed_body.fetch('meta')).to include('total' => 1, 'per_page' => 100)
    expect(response.parsed_body.fetch('items').first).to include('name' => 'SYNTHETIC page 22')
  end

  [{ q: ['x'] }, { status: 'published' }, { page: ['1'] }, { unit_id: { id: 1 } }, { unit_id: '9999999999999999999' }].each do |filter|
    it "rejects malformed filters instead of dropping restrictions #{filter.inspect}" do
      get url, headers: headers, params: filter
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'invalid_ivr_filter')
      expect(response.parsed_body).not_to have_key('items')
    end
  end

  it 'reads bounded history and exports only the selected authorized local JSON schema' do
    original = initial
    get "#{url}/#{original['id']}/versions", headers: headers
    expect(response.parsed_body.fetch('meta')).to include('per_page' => 20, 'total' => 1)
    expect(response.parsed_body.fetch('items').first).not_to have_key('definition')
    get "#{url}/#{original['id']}/export", headers: headers, params: { revision: 1 }
    expect(response).to have_http_status(:ok)
    expect(response.headers['X-JRC-IVR-Revision']).to eq('1')
    expect(response.headers['Content-Disposition']).to include('attachment', "ura-local-#{original['id']}-v1.json")
    expect(response.parsed_body).to eq(JSON.parse(definition.to_json))
    expect(response.body).not_to include('account_id', 'provider', 'actor', 'scope_snapshot')
  end

  it 'simulates an unsaved definition and an exact persisted revision without provider or call side effects' do
    original = initial
    before = [JrcContactCenter::CallSession.count, JrcContactCenter::Command.count, JrcContactCenter::EventInbox.count]
    post "#{url}/preview", headers: headers, params: { ivr_preview: { unit_id: unit.id, definition: definition, dtmf: '' } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('simulation')).to include('outcome' => 'ended', 'provider_applied' => false, 'local_only' => true)
    post "#{url}/#{original['id']}/simulate", headers: headers, params: { ivr_simulation: { revision: 1, dtmf: '' } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('revision' => 1)
    expect(response.parsed_body.fetch('simulation').fetch('trace')).to eq([{ 'node_id' => 'end', 'type' => 'end' }])
    expect([JrcContactCenter::CallSession.count, JrcContactCenter::Command.count, JrcContactCenter::EventInbox.count]).to eq(before)
  end

  it 'does not serve another account draft, history, export or simulation through a known ID' do
    foreign_account = create(:account)
    foreign_actor = create(:user, :contact_center_eligible, account: foreign_account, role: :administrator)
    foreign_account.enable_features!('jrc_contact_center')
    foreign_unit = JrcContactCenter::Unit.create!(account: foreign_account, code: 'FOREIGN', name: 'SYNTHETIC foreign', kind: 'sac')
    foreign_context = { account: foreign_account, account_user: foreign_account.account_users.find_by!(user: foreign_actor), user: foreign_actor }
    input = JrcContactCenter::IvrDraftInput.new(**values.except(:unit_id), definition: JSON.parse(definition.to_json))
    foreign = JrcContactCenter::IvrDraftWrite.new(context: foreign_context).call(input: input, unit_id: foreign_unit.id).fetch(:draft)
    ["#{url}/#{foreign.id}", "#{url}/#{foreign.id}/versions", "#{url}/#{foreign.id}/export?revision=1"].each do |target|
      get target, headers: headers
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('SYNTHETIC draft')
    end
    post "#{url}/#{foreign.id}/simulate", headers: headers, params: { ivr_simulation: { revision: 1, dtmf: '' } }, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'reauthorizes every endpoint after individual eligibility is revoked with the same token' do
    original = initial
    JrcContactCenter::AccessGrant.find_by!(account_user: member).update!(eligible: false)
    get url, headers: headers
    expect(response).to have_http_status(:unauthorized)
    get "#{url}/#{original['id']}/export", headers: headers, params: { revision: 1 }
    expect(response).to have_http_status(:unauthorized)
    post "#{url}/preview", headers: headers, params: { ivr_preview: { unit_id: unit.id, definition: definition, dtmf: '' } }, as: :json
    expect(response).to have_http_status(:unauthorized)
    patch "#{url}/#{original['id']}", headers: headers,
                                      params: { ivr_draft: values.merge(expected_revision: 1, request_id: SecureRandom.uuid) }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::IvrDraftVersion.where(account: account).count).to eq(1)
  end

  it 'filters all draft/preview/simulation payloads before Rails request logging' do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    payload = { 'ivr_draft' => values, 'ivr_preview' => { 'dtmf' => '123#' }, 'ivr_simulation' => { 'dtmf' => '456*' } }
    filtered = filter.filter(payload)
    expect(filtered.values).to all(eq('[FILTERED]'))
    expect(filtered.to_json).not_to include('123#', '456*', 'SYNTHETIC draft')
  end

  it 'reuses the scoped native audit API with explicit revision type and no graph content' do
    account.enable_features!('audit_logs')
    role = create(:custom_role, account: account,
                                permissions: %w[jrc_contact_center_view jrc_contact_center_configure jrc_contact_center_audit])
    member.update!(custom_role: role)
    row = initial
    version = JrcContactCenter::IvrDraft.find(row.fetch('id')).latest_version
    audit = Audited.audit_class.find_by!(auditable: version)
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/configuration_audits/#{audit.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('item')).to include('resource_type' => 'ivr_revision', 'resource_id' => version.id)
    expect(response.parsed_body.fetch('item').fetch('after').keys).to contain_exactly('revision', 'status', 'integrity_sha256')
    expect(response.body).not_to include('SYNTHETIC draft', '"nodes"', operator.email)
  end

  %i[leading_zero newline float oversized missing array].each do |kind|
    it "does not reinterpret a malformed creation unit identity #{kind}" do
      identifier = { leading_zero: "0#{unit.id}", newline: "#{unit.id}\n", float: unit.id.to_f,
                     oversized: '9999999999999999999', missing: nil, array: [unit.id] }.fetch(kind)
      post url, headers: headers, params: { ivr_draft: values.merge(unit_id: identifier) }, as: :json
      expect(response).to have_http_status(:not_found)
      expect(JrcContactCenter::IvrDraft.where(account: account)).to be_empty
    end
  end

  it 'does not expose saved drafts after the native feature is disabled' do
    row = initial
    account.disable_features!('jrc_contact_center')
    get url, headers: headers
    expect(response).to have_http_status(:unauthorized)
    get "#{url}/#{row.fetch('id')}", headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('SYNTHETIC draft')
  end
end
