require 'rails_helper'

RSpec.describe 'Institutional audio duplication uses the native receipt and account/unit authority', type: :request do
  include_context 'with an institutional audio receipt'

  let(:headers) { actor.create_new_auth_token }
  let(:source_version) do
    JrcContactCenter::AudioUploads.new(access: JrcContactCenter::AudioLibraryAccess.new(context: context))
                                  .create!(unit_id: unit.id, attributes: { name: 'SYNTHETIC copy source' }, file: upload, key: key)
  end
  let(:endpoint) { "/api/v1/accounts/#{account.id}/jrc_contact_center/audio_assets/#{source_version.audio_asset_id}/duplicate" }
  let(:body) do
    { asset: { name: 'SYNTHETIC independent copy' }, source_version_id: source_version.id.to_s,
      expected_revision: JrcContactCenter::AudioAssetRevision.token(source_version.audio_asset, version: source_version),
      idempotency_key: 'synthetic-http-audio-copy-0001' }
  end

  it 'persists an independent identity, version one and private bytes through the real native inspection' do
    post endpoint, headers: headers, params: body, as: :json
    expect(response).to have_http_status(:created)
    result = response.parsed_body
    version = JrcContactCenter::AudioVersion.find(result.fetch('received_version').fetch('id'))
    expect(result.fetch('item')).to include('name' => 'SYNTHETIC independent copy', 'unit_id' => unit.id.to_s)
    expect(version).to have_attributes(number: 1, sha256: source_version.sha256, byte_size: source_version.byte_size)
    expect([version.audio_asset_id != source_version.audio_asset_id, version.blob_id != source_version.blob_id]).to eq([true, true])
    expect([version.blob.download, version.reload.latest_inspection.ready?]).to eq([bytes, true])
    expect(response.headers['Cache-Control']).to eq('no-store')
    expect(response.body).not_to match(/signed_id|blob_id|service_url|idempotency_key|input_digest/)
  end

  it 'returns the same receipt after a lost response instead of creating another asset or file' do
    post endpoint, headers: headers, params: body, as: :json
    first = response.parsed_body
    initial = [JrcContactCenter::AudioAsset.count, JrcContactCenter::AudioVersion.count, ActiveStorage::Blob.count]
    post endpoint, headers: headers, params: body, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.fetch('received_version').fetch('id')).to eq(first.fetch('received_version').fetch('id'))
    expect([JrcContactCenter::AudioAsset.count, JrcContactCenter::AudioVersion.count, ActiveStorage::Blob.count]).to eq(initial)
  end

  it 'rejects reuse of a committed request key for a different copy instead of silently changing the destination' do
    payload = body
    post endpoint, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:created)
    post endpoint, headers: headers, params: payload.merge(asset: { name: 'SYNTHETIC different intention' }), as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('institutional_audio_upload_key_conflict')
    expect(JrcContactCenter::AudioVersion.where(account: account).count).to eq(2)
  end

  it 'requires an actual reviewed source revision and rejects a stale precondition' do
    payload = body
    post endpoint, headers: headers, params: payload.except(:expected_revision), as: :json
    expect(response).to have_http_status(:precondition_required)
    source_version.audio_asset.update!(name: 'SYNTHETIC changed source')
    post endpoint, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.fetch('error')).to eq('stale_configuration_revision')
    expect(JrcContactCenter::AudioVersion.where(account: account).count).to eq(1)
  end

  it 'does not grant authority through account, user or unit parameters supplied in the body' do
    payload = body
    %i[account_id user_id unit_id].each do |field|
      post endpoint, headers: headers, params: payload.merge(field => 99_999), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(JrcContactCenter::AudioVersion.where(account: account).count).to eq(1)
  end

  it 'rejects another native unit and foreign destination folders without leaking private names' do
    payload = body
    hidden = JrcContactCenter::AudioAsset.create!(account: account, unit: units.last, name: 'SYNTHETIC hidden source')
    folder = JrcContactCenter::AudioFolder.create!(account: account, unit: units.last, name: 'SYNTHETIC hidden destination')
    post endpoint.sub("/#{source_version.audio_asset_id}/duplicate", "/#{hidden.id}/duplicate"), headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(hidden.name)
    post endpoint, headers: headers, params: payload.merge(asset: { name: 'SYNTHETIC invalid copy', folder_id: folder.id }), as: :json
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(folder.name)
    expect(JrcContactCenter::AudioVersion.where(account: account).count).to eq(1)
  end

  it 'cannot select another account source through its global record ID' do
    payload = body
    other = create(:account)
    hidden_unit = JrcContactCenter::Unit.create!(account: other, code: 'COPY-HIDDEN', name: 'SYNTHETIC foreign unit', kind: 'sac')
    hidden = JrcContactCenter::AudioAsset.create!(account: other, unit: hidden_unit, name: 'SYNTHETIC foreign audio')
    post endpoint.sub("/#{source_version.audio_asset_id}/duplicate", "/#{hidden.id}/duplicate"), headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(hidden.name)
    expect(JrcContactCenter::AudioVersion.where(account: account).count).to eq(1)
    expect(JrcContactCenter::AudioVersion.where(account: other)).to be_empty
  end

  it 'reevaluates a withdrawn profile and never treats telephone-recording access as configure permission' do
    payload = body
    member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_recordings_listen])
    post endpoint, headers: headers, params: payload, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcContactCenter::AudioVersion.where(account: account).count).to eq(1)
    expect(source_version.reload.blob.download).to eq(bytes)
  end

  it 'exposes only the allowlisted copy lineage in the native scoped audit history' do
    post endpoint, headers: headers, params: body, as: :json
    version_id = response.parsed_body.fetch('received_version').fetch('id')
    audits = "/api/v1/accounts/#{account.id}/jrc_contact_center/configuration_audits"
    get audits, headers: headers, params: { resource_type: 'audio_version', resource_id: version_id, history: 'true', operation: 'copy' }
    expect(response).to have_http_status(:ok)
    items = response.parsed_body.fetch('items')
    expect(items.length).to eq(1)
    expect(items.first.fetch('audio_copy')).to eq('source_asset_id' => source_version.audio_asset_id.to_s,
                                                'source_version_id' => source_version.id.to_s, 'source_sha256' => source_version.sha256)
    expect(items.first.dig('scopes', 'after', 'unit_id')).to eq(unit.id.to_s)
    expect(response.body).not_to include(source_version.file_name, source_version.blob.key, source_version.idempotency_key)
  end
end
