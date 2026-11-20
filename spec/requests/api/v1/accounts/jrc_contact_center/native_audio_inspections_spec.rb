require 'rails_helper'

# Real Linux binaries + an exclusively synthetic signature DB. This is not malware coverage or external homologation.
RSpec.describe 'Institutional audio native scanner and decoder receipts', type: :request do
  include_context 'with an institutional audio receipt'

  let(:headers) { actor.create_new_auth_token }
  let(:version) do
    JrcContactCenter::AudioUploads.new(access: JrcContactCenter::AudioLibraryAccess.new(context: context))
                                 .create!(unit_id: unit.id, attributes: { name: 'SYNTHETIC native inspection' }, file: upload, key: key)
  end
  let(:base) { "/api/v1/accounts/#{account.id}/jrc_contact_center/audio_assets/#{version.audio_asset_id}/versions/#{version.id}/inspections" }

  before do
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted'
    owned &&= ENV.fetch('JRC_CC_AUDIO_CLAMAV_SOCKET', '').start_with?('/run/jrc-cc-audio-')
    raise 'Native audio proof requires the owned synthetic Linux tools, not another scanner' unless owned

    tools = JSON.parse(File.read('/tmp/call-center-audio-native-tools.json'))
    expected = { 'signature_database' => 'SYNTHETIC_TEST_ONLY', 'malware_coverage_proven' => false, 'external_homologation' => false,
                 'certificate_sha256' => '60200e4b4b1b1b7257bb4550487aeb142034341f3300a8526e77a3134a940e9d' }
    valid = tools.slice(*expected.keys) == expected && tools['actual_engine'].is_a?(String) && tools['actual_engine'].start_with?('ClamAV ')
    raise 'Owned synthetic ClamAV engine identity required; no malware coverage is implied' unless valid
  end

  it 'persists a real scan, exact digest and decoded metadata without publishing or returning any private locator' do
    post base, headers: headers, params: { idempotency_key: 'synthetic-native-inspection-0001' }, as: :json
    expect(response).to have_http_status(:created)
    item = response.parsed_body.fetch('item')
    expect(item).to include('state' => 'clean', 'probe_state' => 'valid', 'ready' => true, 'observed_sha256' => version.sha256)
    expect(item.fetch('metadata')).to include('container' => 'wav', 'codec' => 'pcm_s16le', 'sample_rate' => 8_000, 'channels' => 1)
    expect(item.fetch('decoder_version')).to start_with('ffmpeg version ')
    expect(response.body).not_to include(version.blob.key, version.blob.signed_id, version.idempotency_key)
  end

  it 'detects the harmless byte marker with the actual engine and does not decode or clear that version' do
    marked = bytes.dup
    marked.setbyte(marked.bytesize - 1, 1)
    Tempfile.create(['SYNTHETIC-native-marker', '.wav']) do |file|
      file.binmode
      file.write(marked)
      file.flush
      native_upload = ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: 'SYNTHETIC-marker.wav', type: 'audio/wav')
      record = JrcContactCenter::AudioUploads.new(access: JrcContactCenter::AudioLibraryAccess.new(context: context))
                                           .create!(unit_id: unit.id, attributes: { name: 'SYNTHETIC marker only' }, file: native_upload, key: key)
      path = "/api/v1/accounts/#{account.id}/jrc_contact_center/audio_assets/#{record.audio_asset_id}/versions/#{record.id}/inspections"
      post path, headers: headers, params: { idempotency_key: 'synthetic-native-inspection-0001' }, as: :json
      expect(response).to have_http_status(:created)
      expect(response.parsed_body.fetch('item')).to include('state' => 'infected', 'probe_state' => 'not_run', 'ready' => false, 'metadata' => {})
    end
  end

  it 'keeps a genuinely scanner-clean but undecodable empty WAV header blocked without invented duration' do
    with_modified_env JRC_CC_AUDIO_CLAMAV_SOCKET: ENV.fetch('JRC_CC_AUDIO_CLAMAV_SOCKET') do
      Tempfile.create(['SYNTHETIC-empty-native', '.wav']) do |file|
        file.binmode
        file.write(bytes.byteslice(0, 44))
        file.flush
        native_upload = ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: 'SYNTHETIC-empty.wav', type: 'audio/wav')
        record = JrcContactCenter::AudioUploads.new(access: JrcContactCenter::AudioLibraryAccess.new(context: context))
                                             .create!(unit_id: unit.id, attributes: { name: 'SYNTHETIC empty header' }, file: native_upload, key: key)
        path = "/api/v1/accounts/#{account.id}/jrc_contact_center/audio_assets/#{record.audio_asset_id}/versions/#{record.id}/inspections"
        post path, headers: headers, params: { idempotency_key: 'synthetic-native-inspection-0001' }, as: :json
        expect(response).to have_http_status(:created)
        expect(response.parsed_body.fetch('item')).to include('state' => 'clean', 'probe_state' => 'invalid', 'ready' => false, 'metadata' => {})
      end
    end
  end

  it 'preserves an unavailable attempt and appends a later real inspection rather than overwriting evidence' do
    with_modified_env JRC_CC_AUDIO_CLAMAV_SOCKET: '/run/jrc-cc-audio-nonexistent-synthetic/clamd.sock' do
      post base, headers: headers, params: { idempotency_key: 'synthetic-native-inspection-0001' }, as: :json
      expect(response).to have_http_status(:created)
      expect(response.parsed_body.fetch('item')).to include('state' => 'unavailable', 'ready' => false, 'attempt' => 1)
    end
    post base, headers: headers, params: { idempotency_key: 'synthetic-native-inspection-0002' }, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.fetch('item')).to include('state' => 'clean', 'probe_state' => 'valid', 'ready' => true, 'attempt' => 2)
    expect(JrcContactCenter::AudioInspection.where(audio_version: version).order(:attempt).pluck(:state)).to eq(%w[unavailable clean])
  end

  it 'replays a native accepted operation and does not create another observation after its response is lost' do
    params = { idempotency_key: 'synthetic-native-inspection-0001' }
    post base, headers: headers, params: params, as: :json
    expect(response).to have_http_status(:created)
    first = response.parsed_body.fetch('item').slice('id', 'created_at', 'observed_at', 'metadata')
    post base, headers: headers, params: params, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.fetch('item').slice('id', 'created_at', 'observed_at', 'metadata')).to eq(first)
    expect(JrcContactCenter::AudioInspection.where(audio_version: version).count).to eq(1)
  end
end
