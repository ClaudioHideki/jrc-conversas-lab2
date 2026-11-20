require 'rails_helper'

RSpec.describe 'Institutional audio admission authenticates and validates before final persistence', type: :request do
  include_context 'with an institutional audio receipt'

  let(:headers) { actor.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center/audio_assets" }
  let(:incoming) { Rack::Test::UploadedFile.new(StringIO.new(bytes), 'audio/wav', original_filename: 'SYNTHETIC.wav') }
  let(:payload) { { asset: { name: 'SYNTHETIC admission' }, unit_id: unit.id, file: incoming, idempotency_key: key } }

  after { incoming.close }

  it 'saves an exact native observation and permits only separately authorized and rehashed bytes' do
    post base, headers: headers, params: payload
    expect(response).to have_http_status(:created)
    version = response.parsed_body.fetch('received_version')
    get "#{base}/#{version.fetch('audio_asset_id')}/versions/#{version.fetch('id')}/inspections", headers: headers
    proof = response.parsed_body.fetch('items').sole
    expect(proof).to include('ready' => true, 'state' => 'clean', 'probe_state' => 'valid', 'attempt' => 1)
    expect(proof.fetch('expected_sha256')).to eq(Digest::SHA256.hexdigest(bytes))
    get "#{base}/#{version.fetch('audio_asset_id')}/versions/#{version.fetch('id')}/bytes", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body.b).to eq(bytes)
    expect(response.headers['Cache-Control']).to eq('no-store')
  end

  it 'rejects a scanner-clean empty WAV rather than presenting a persisted unusable row' do
    incoming.tempfile.truncate(44)
    incoming.tempfile.rewind
    original_blobs = ActiveStorage::Blob.count
    post base, headers: headers, params: payload
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('institutional_audio_invalid_codec')
    expect(JrcContactCenter::AudioAsset.where(account: account)).to be_empty
    expect(JrcContactCenter::AudioVersion.where(account: account)).to be_empty
    expect(JrcContactCenter::AudioInspection.where(account: account)).to be_empty
    expect(ActiveStorage::Blob.count).to eq(original_blobs)
  end

  it 'rejects the harmless native scanner marker without a final receipt or a private storage locator' do
    incoming.tempfile.seek(bytes.bytesize - 1)
    incoming.tempfile.write("\1")
    incoming.tempfile.rewind
    post base, headers: headers, params: payload
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch('error')).to eq('institutional_audio_unsafe_file')
    expect(JrcContactCenter::AudioVersion.where(account: account)).to be_empty
    expect(JrcContactCenter::AudioInspection.where(account: account)).to be_empty
    expect(response.body).not_to match(/blob_id|signed_id|service_url|idempotency_key/)
  end

  it 'reports an explicit unavailable admission without accepting a request or releasing bytes' do
    with_modified_env JRC_CC_AUDIO_CLAMAV_SOCKET: nil do
      post base, headers: headers, params: payload
    end
    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body.fetch('error')).to eq('institutional_audio_inspection_unavailable')
    expect(JrcContactCenter::AudioAsset.where(account: account)).to be_empty
    expect(JrcContactCenter::AudioVersion.where(account: account)).to be_empty
    expect(JrcContactCenter::AudioInspection.where(account: account)).to be_empty
  end
end
