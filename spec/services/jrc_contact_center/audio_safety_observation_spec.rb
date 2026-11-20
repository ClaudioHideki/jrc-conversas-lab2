require 'rails_helper'

RSpec.describe JrcContactCenter::AudioSafetyObservation do
  include_context 'with an institutional audio receipt'

  let(:access) { JrcContactCenter::AudioLibraryAccess.new(context: context) }
  let(:version) do
    legacy = JrcContactCenter::SyntheticLegacyAudioReceipt.new(access: access)
    legacy.create!(unit_id: unit.id, attributes: { name: 'SYNTHETIC observation' }, file: upload, key: key)
  end
  let(:scanner) do
    # Dependency contract fixture only. It is not a real ClamAV/homologation proof.
    instance_double(JrcServiceDesk::AttachmentScanner, scan: {
                      'service_desk_scan_state' => 'clean', 'service_desk_scan_adapter' => 'clamav-instream-v1',
                      'service_desk_scan_sha256' => version.sha256, 'service_desk_scanned_at' => Time.current.iso8601(6)
                    })
  end
  let(:probe) do
    instance_double(JrcContactCenter::AudioMediaProbe, call: {
                      state: 'valid', decoder_version: 'ffmpeg version SYNTHETIC contract fixture',
                      metadata: { 'container' => 'wav', 'codec' => 'pcm_s16le', 'content_type' => 'audio/wav',
                                  'duration_ms' => 1, 'sample_rate' => 8_000, 'channels' => 1,
                                  'probe_version' => 'ffprobe version SYNTHETIC contract fixture' }
                    })
  end

  it 'correlates actual own stored bytes with substituted dependency contracts without persisting or releasing them' do
    result = described_class.new(access: access, scanner: scanner, probe: probe).call(asset_id: version.audio_asset_id, version_id: version.id)
    expect(result.version.id).to eq(version.id)
    expect(result.attributes).to include(state: 'clean', probe_state: 'valid', observed_sha256: version.sha256)
    expect(result.attributes.fetch(:metadata).keys.sort).to eq(JrcContactCenter::AudioMediaMetadata::FIELDS.sort)
    expect(result.attributes.to_json).not_to include(version.blob.key, version.file_name, version.idempotency_key)
    expect(version.reload.blob.download).to eq(bytes)
  end

  it 'uses the native disabled-scanner result as unavailable and never runs the decoder or fabricates clean' do
    with_modified_env JRC_CC_AUDIO_CLAMAV_SOCKET: nil do
      expect(probe).not_to receive(:call)
      result = described_class.new(access: access, probe: probe).call(asset_id: version.audio_asset_id, version_id: version.id)
      expect(result.attributes).to include(state: 'unavailable', probe_state: 'not_run', metadata: {}, decoder_version: nil)
    end
  end

  it 'rejects a clean dependency response for different bytes before calling the media parser' do
    allow(scanner).to receive(:scan).and_return('service_desk_scan_state' => 'clean', 'service_desk_scan_adapter' => 'clamav-instream-v1',
                                                'service_desk_scan_sha256' => 'f' * 64, 'service_desk_scanned_at' => Time.current.iso8601(6))
    expect(probe).not_to receive(:call)
    result = described_class.new(access: access, scanner: scanner, probe: probe).call(asset_id: version.audio_asset_id, version_id: version.id)
    expect(result.attributes).to include(state: 'checksum_mismatch', probe_state: 'not_run', metadata: {})
  end

  it 'keeps infected media private without decoding it or converting the result to clean' do
    response = scanner.scan(nil).merge('service_desk_scan_state' => 'infected')
    allow(scanner).to receive(:scan).and_return(response)
    expect(probe).not_to receive(:call)
    result = described_class.new(access: access, scanner: scanner, probe: probe).call(asset_id: version.audio_asset_id, version_id: version.id)
    expect(result.attributes).to include(state: 'infected', probe_state: 'not_run', metadata: {})
  end

  it 'does not trust a MIME type or partial metadata supplied by a dependency as a valid playable observation' do
    allow(probe).to receive(:call).and_return(state: 'valid', metadata: { 'duration_ms' => 1 }, decoder_version: 'ffmpeg version SYNTHETIC')
    result = described_class.new(access: access, scanner: scanner, probe: probe).call(asset_id: version.audio_asset_id, version_id: version.id)
    expect(result.attributes).to include(state: 'clean', probe_state: 'unavailable', metadata: {}, decoder_version: nil)
  end

  it 'rejects native storage corruption before either dependency can report an approval' do
    original = version
    original.blob.service.upload(original.blob.key, StringIO.new('SYNTHETIC corrupted own bytes'))
    expect(scanner).not_to receive(:scan)
    expect(probe).not_to receive(:call)
    result = described_class.new(access: access, scanner: scanner, probe: probe).call(asset_id: original.audio_asset_id, version_id: original.id)
    expect(result.attributes).to include(state: 'checksum_mismatch', probe_state: 'not_run', metadata: {})
    expect(original.reload.sha256).to eq(Digest::SHA256.hexdigest(bytes))
  end

  it 'reports unavailable for a missing owned synthetic file without invoking either dependency or inventing metadata' do
    original = version
    JrcContactCenter::SyntheticAudioStorageGuard.call
    original.blob.service.delete(original.blob.key)
    expect(scanner).not_to receive(:scan)
    expect(probe).not_to receive(:call)
    result = described_class.new(access: access, scanner: scanner, probe: probe).call(asset_id: original.audio_asset_id, version_id: original.id)
    expect(result.attributes).to include(state: 'unavailable', probe_state: 'not_run', metadata: {}, observed_sha256: nil)
    expect(original.reload.sha256).to eq(Digest::SHA256.hexdigest(bytes))
  end

  it 'rechecks authority after dependency IO instead of returning a result from an earlier permitted profile' do
    original = version
    response = scanner.scan(nil)
    allow(scanner).to receive(:scan) do
      member.custom_role.update!(permissions: %w[jrc_contact_center_view])
      response
    end
    expect do
      described_class.new(access: access, scanner: scanner, probe: probe).call(asset_id: original.audio_asset_id, version_id: original.id)
    end.to raise_error(Pundit::NotAuthorizedError)
    expect(original.reload.blob.download).to eq(bytes)
  end

  it 'does not inspect an asset outside current native unit coverage' do
    hidden = JrcContactCenter::AudioAsset.create!(account: account, unit: units.last, name: 'SYNTHETIC hidden')
    expect(scanner).not_to receive(:scan)
    expect(probe).not_to receive(:call)
    expect do
      described_class.new(access: access, scanner: scanner, probe: probe).call(asset_id: hidden.id, version_id: version.id)
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'bounds the combined inspection and retains fail-closed semantics when the owned deadline is reached' do
    original = version
    allow(Timeout).to receive(:timeout).with(45, described_class::Deadline).and_raise(described_class::Deadline)
    expect(scanner).not_to receive(:scan)
    expect(probe).not_to receive(:call)
    result = described_class.new(access: access, scanner: scanner, probe: probe).call(asset_id: original.audio_asset_id, version_id: original.id)
    expect(result.attributes).to include(state: 'unavailable', probe_state: 'not_run', metadata: {}, observed_sha256: nil)
  end
end
