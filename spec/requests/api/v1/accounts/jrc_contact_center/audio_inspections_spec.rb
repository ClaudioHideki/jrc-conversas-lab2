require 'rails_helper'

RSpec.describe 'Institutional audio inspection authority and native persistence', type: :request do
  include_context 'with an institutional audio receipt'

  let(:headers) { actor.create_new_auth_token }
  let(:version) do
    JrcContactCenter::AudioUploads.new(access: JrcContactCenter::AudioLibraryAccess.new(context: context))
                                  .create!(unit_id: unit.id, attributes: { name: 'SYNTHETIC inspectable audio' }, file: upload, key: key)
  end
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center/audio_assets/#{version.audio_asset_id}/versions/#{version.id}/inspections" }

  around do |example|
    with_modified_env JRC_CC_AUDIO_CLAMAV_SOCKET: nil do
      example.run
    end
  end

  it 'records the native unavailable scanner state instead of fabricating clearance, metadata or a public locator' do
    post base, headers: headers, params: { idempotency_key: 'synthetic-inspection-http-0001' }, as: :json
    expect(response).to have_http_status(:created)
    item = response.parsed_body.fetch('item')
    expect(item).to include('state' => 'unavailable', 'probe_state' => 'not_run', 'ready' => false, 'metadata' => {})
    expect(item).to include('unit_id' => unit.id.to_s, 'audio_version_id' => version.id.to_s, 'attempt' => 1)
    expect(item.fetch('observed_sha256')).to eq(version.sha256)
    expect(response.headers['Cache-Control']).to eq('no-store')
    expect(response.body).not_to match(/source_blob_id|signed_id|service_url|idempotency_key|input_digest/)
  end

  it 'replays an accepted uncertain request without adding a second observation or audit event' do
    params = { idempotency_key: 'synthetic-inspection-http-0001' }
    post base, headers: headers, params: params, as: :json
    expect(response).to have_http_status(:created)
    first = response.parsed_body.fetch('item').fetch('id')
    post base, headers: headers, params: params, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.fetch('item').fetch('id')).to eq(first)
    expect(JrcContactCenter::AudioInspection.where(account: account, audio_version: version).count).to eq(1)
    expect(Audited.audit_class.where(auditable_type: 'JrcContactCenter::AudioInspection', auditable_id: first, action: 'create').count).to eq(1)
  end

  it 'bounds exact-version history while keeping a deliberately requested fresh attempt distinct' do
    2.times do |index|
      post base, headers: headers, params: { idempotency_key: "synthetic-inspection-http-000#{index}" }, as: :json
      expect(response).to have_http_status(:created)
    end
    get base, headers: headers, params: { page: 1, per_page: 1 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('meta')).to include('page' => 1, 'pages' => 2, 'total' => 2, 'per_page' => 1)
    expect(response.parsed_body.fetch('items').pluck('attempt')).to eq([2])
  end

  it 'does not accept client-shaped state, metadata, actor or account declarations as technical proof' do
    post base, headers: headers, params: { idempotency_key: 'synthetic-inspection-http-0001', state: 'clean', ready: true,
                                           metadata: { duration_ms: 1 }, user_id: actor.id, account_id: account.id }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::AudioInspection.where(account: account)).to be_empty
    expect(version.reload.blob.download).to eq(bytes)
  end

  it 'does not disclose or inspect an asset outside current native unit coverage through a nested version ID' do
    hidden = JrcContactCenter::AudioAsset.create!(account: account, unit: units.last, name: 'SYNTHETIC hidden inspection source')
    denied = "/api/v1/accounts/#{account.id}/jrc_contact_center/audio_assets/#{hidden.id}/versions/#{version.id}/inspections"
    get denied, headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(hidden.name)
    post denied, headers: headers, params: { idempotency_key: 'synthetic-inspection-http-0001' }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(JrcContactCenter::AudioInspection.where(account: account)).to be_empty
  end

  it 'rechecks the current profile for reads and writes without deleting already accepted technical history' do
    post base, headers: headers, params: { idempotency_key: 'synthetic-inspection-http-0001' }, as: :json
    expect(response).to have_http_status(:created)
    record_id = response.parsed_body.fetch('item').fetch('id')
    member.custom_role.update!(permissions: %w[jrc_contact_center_view])
    get base, headers: headers
    expect(response).to have_http_status(:unauthorized)
    post base, headers: headers, params: { idempotency_key: 'synthetic-inspection-http-0002' }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::AudioInspection.where(account: account).pluck(:id)).to eq([record_id.to_i])
  end

  it 'does not resolve a foreign account asset through an otherwise valid local unit and version' do
    other = create(:account)
    foreign_unit = JrcContactCenter::Unit.create!(account: other, code: 'FOREIGN', name: 'SYNTHETIC foreign inspection', kind: 'sac')
    foreign = JrcContactCenter::AudioAsset.create!(account: other, unit: foreign_unit, name: 'SYNTHETIC foreign audio')
    denied = "/api/v1/accounts/#{account.id}/jrc_contact_center/audio_assets/#{foreign.id}/versions/#{version.id}/inspections"
    get denied, headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(foreign.name)
    post denied, headers: headers, params: { idempotency_key: 'synthetic-inspection-http-0001' }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(JrcContactCenter::AudioInspection.where(account: [account, other])).to be_empty
    expect(version.reload.blob.download).to eq(bytes)
  end
end
