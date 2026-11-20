require 'rails_helper'

RSpec.describe 'Private institutional audio receipts reuse native account and unit authority', type: :request do
  include_context 'institutional audio receipt'

  let(:headers) { actor.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center/audio_assets" }
  let(:receipt) do
    JrcContactCenter::AudioUploads.new(access: JrcContactCenter::AudioLibraryAccess.new(context: context))
                                 .create!(unit_id: unit.id, attributes: { name: 'SYNTHETIC private message' }, file: upload, key: key)
  end

  it 'accepts actual multipart bytes and presents metadata without a signed locator, storage key or readiness claim' do
    post base, headers: headers,
               params: { asset: { name: 'SYNTHETIC received message' }, unit_id: unit.id, file: upload, idempotency_key: key }
    expect(response).to have_http_status(:created)
    item = response.parsed_body.fetch('item')
    expect(item).to include('unit_id' => unit.id.to_s, 'name' => 'SYNTHETIC received message')
    expect(item.fetch('latest_version')).to include('number' => 1, 'ready' => false, 'security_state' => 'not_verified')
    expect(response.headers['Cache-Control']).to eq('no-store')
    expect(response.body).not_to match(/signed_id|blob_id|service_url|idempotency_key|input_digest/)
    expect(item.fetch('revision')).to match(/\A[0-9a-f]{64}\z/)
  end

  it 'bounds native pagination and persists reviewed rename and reorganization within the exact same unit' do
    asset = receipt.audio_asset
    folder = JrcContactCenter::AudioFolder.create!(account: account, unit: unit, name: 'SYNTHETIC destination')
    get base, headers: headers, params: { unit_id: unit.id, per_page: 1 }
    expect(response.parsed_body.fetch('meta')).to include('page' => 1, 'per_page' => 1, 'total' => 1)
    expected = response.parsed_body.fetch('items').first.fetch('revision')
    patch "#{base}/#{asset.id}", headers: headers,
                                params: { asset: { name: 'SYNTHETIC renamed', folder_id: folder.id.to_s }, expected_revision: expected }, as: :json
    expect(response).to have_http_status(:ok)
    expect(asset.reload).to have_attributes(name: 'SYNTHETIC renamed', folder_id: folder.id, unit_id: unit.id)
    expect(receipt.reload.blob.download).to eq(bytes)
    get base, headers: headers, params: { unit_id: unit.id, folder_id: '', page: 1 }
    expect(response.parsed_body.fetch('items')).to be_empty
  end

  it 'rejects stale metadata edits and does not silently replace another reviewed version' do
    asset = receipt.audio_asset
    expected = JrcContactCenter::AudioAssetRevision.token(asset, version: receipt)
    patch "#{base}/#{asset.id}", headers: headers,
                                params: { asset: { name: 'SYNTHETIC first edit' }, expected_revision: expected }, as: :json
    expect(response).to have_http_status(:ok)
    patch "#{base}/#{asset.id}", headers: headers,
                                params: { asset: { name: 'SYNTHETIC stale edit' }, expected_revision: expected }, as: :json
    expect(response).to have_http_status(:conflict)
    expect(asset.reload.name).to eq('SYNTHETIC first edit')
  end

  it 'requires a revision for replacement and returns a bounded immutable version history' do
    asset = receipt.audio_asset
    endpoint = "#{base}/#{asset.id}/versions"
    post endpoint, headers: headers, params: { file: upload, idempotency_key: 'synthetic-audio-request-0002' }
    expect(response).to have_http_status(:precondition_required)
    expected = JrcContactCenter::AudioAssetRevision.token(asset, version: receipt)
    post endpoint, headers: headers,
                   params: { file: upload, idempotency_key: 'synthetic-audio-request-0002', expected_revision: expected }
    expect(response).to have_http_status(:created)
    get endpoint, headers: headers, params: { page: 1, per_page: 1 }
    expect(response.parsed_body.fetch('items').pluck('number')).to eq([2])
    expect(response.parsed_body.fetch('meta')).to include('pages' => 2, 'total' => 2)
    expect(response.body).not_to include(receipt.blob.key, receipt.idempotency_key)
  end

  it 'does not expose another native unit through list, item, folder binding or version history' do
    hidden_folder = JrcContactCenter::AudioFolder.create!(account: account, unit: units.last, name: 'SYNTHETIC denied folder')
    hidden = JrcContactCenter::AudioAsset.create!(account: account, unit: units.last, name: 'SYNTHETIC denied audio')
    get base, headers: headers, params: { unit_id: units.last.id }
    expect(response).to have_http_status(:not_found)
    get "#{base}/#{hidden.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    get "#{base}/#{hidden.id}/versions", headers: headers
    expect(response).to have_http_status(:not_found)
    post base, headers: headers, params: { asset: { name: 'SYNTHETIC forged folder', folder_id: hidden_folder.id },
                                          unit_id: unit.id, file: upload, idempotency_key: key }
    expect(response).to have_http_status(:not_found)
    expect(JrcContactCenter::AudioVersion.where(account: account)).to be_empty
  end

  it 'does not let a foreign account ID select audio in the current account or an explicit actor override authority' do
    other = create(:account)
    foreign_unit = JrcContactCenter::Unit.create!(account: other, code: 'FOREIGN', name: 'SYNTHETIC foreign', kind: 'sac')
    foreign = JrcContactCenter::AudioAsset.create!(account: other, unit: foreign_unit, name: 'SYNTHETIC foreign audio')
    get "#{base}/#{foreign.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(foreign.name)
    post base, headers: headers, params: { account_id: other.id, asset: { name: 'SYNTHETIC forged' },
                                          unit_id: unit.id, file: upload, idempotency_key: key }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::AudioVersion.where(account: account)).to be_empty
  end

  it 'clears authority after profile withdrawal and never treats recording access as institutional configuration' do
    original = receipt
    member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_recordings_listen])
    get "#{base}/#{original.audio_asset_id}", headers: headers
    expect(response).to have_http_status(:unauthorized)
    get "#{base}/#{original.audio_asset_id}/versions", headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(original.reload.blob.download).to eq(bytes)
  end

  it 'records actor and exact unit in native audit while omitting filenames, signed locators, request keys and private bytes' do
    original = receipt
    row = Audited.audit_class.where(auditable: original, associated: account).last
    expect(row.audited_changes.dig('cc_scope', 'after', 'unit_id')).to eq(unit.id.to_s)
    expect(row.audited_changes.dig('attributes', 1)).to include('number' => 1, 'sha256' => original.sha256)
    expect(row.audited_changes.to_json).not_to include(original.file_name, original.idempotency_key, original.blob.key, bytes)
    endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/configuration_audits"
    get endpoint, headers: headers, params: { resource_type: 'audio_version', resource_id: original.id, history: 'true' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to include(hash_including('resource_type' => 'audio_version', 'resource_id' => original.id))
  end

  it 'does not expose private bytes through either generic ActiveStorage redirect or proxy, even with an admin session and signed ID' do
    blob = receipt.blob
    get rails_blob_path(blob, only_path: true), headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.headers['Cache-Control']).to eq('no-store')
    get rails_storage_proxy_path(blob, only_path: true), headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(bytes)
  end

  it 'does not receive a caller-supplied blob reference instead of the actual uploaded bytes' do
    post base, headers: headers, params: { asset: { name: 'SYNTHETIC forged blob' }, unit_id: unit.id,
                                          file: { signed_id: receipt.blob.signed_id }, idempotency_key: 'synthetic-audio-request-0002' }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcContactCenter::AudioVersion.where(account: account).count).to eq(1)
  end

  it 'also denies direct disk read and signed upload capabilities from altering or exposing the accepted bytes' do
    blob = receipt.blob
    ActiveStorage::Current.set(url_options: { host: '127.0.0.1', port: 5387, protocol: 'http' }) do
      get URI.parse(blob.url).request_uri
      expect(response).to have_http_status(:not_found)
      url = blob.service.url_for_direct_upload(blob.key, expires_in: 5.minutes, content_type: blob.content_type,
                                                        content_length: blob.byte_size, checksum: blob.checksum)
      put URI.parse(url).request_uri, params: bytes, headers: { 'Content-Type' => 'audio/wav' }
      expect(response).to have_http_status(:not_found)
    end
    expect(blob.download).to eq(bytes)
  end

  it 'preserves ordinary unrelated ActiveStorage redirects without turning an unmarked public upload into institutional audio' do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), filename: 'SYNTHETIC public.wav', content_type: 'audio/wav')
    get rails_blob_path(blob, only_path: true)
    expect(response).to have_http_status(:found)
    expect(JrcContactCenter::AudioVersion.exists?(blob: blob)).to be(false)
    blob.purge
  end

  it 'filters the actual file and private receipt correlators using the native request logger' do
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
                                            .filter({ 'file' => upload, 'idempotency_key' => key, 'input_digest' => 'f' * 64 })
    expect(filtered).to eq('file' => '[FILTERED]', 'idempotency_key' => '[FILTERED]', 'input_digest' => '[FILTERED]')
  end
end
