require 'rails_helper'

# Actual owned native scanner/decoder; definition DB is synthetic and proves no production malware coverage.
RSpec.describe JrcContactCenter::AudioUploads do
  include_context 'with an institutional audio receipt'

  let(:access) { JrcContactCenter::AudioLibraryAccess.new(context: context) }
  let(:service) { described_class.new(access: access) }
  let(:attributes) { { name: 'SYNTHETIC admitted audio' } }
  let(:received) { service.create!(unit_id: unit.id, attributes: attributes, file: upload, key: key) }

  it 'atomically persists an actual clean decoded observation with the exact immutable version' do
    version = received
    proof = access.inspections(version).sole
    expect(proof.ready?).to be(true)
    expect(proof).to have_attributes(attempt: 1, source_blob_id: version.blob_id, expected_sha256: version.sha256,
                                     observed_sha256: version.sha256, created_by_id: actor.id)
    expect(proof.metadata).to include('codec' => 'pcm_s16le', 'duration_ms' => 1)
    expect(Audited.audit_class.where(auditable: proof, action: 'create').count).to eq(1)
    expect(version.blob.download).to eq(bytes)
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
  end

  it 'rejects a clean but undecodable header before any final record or final audit is persisted' do
    upload.tempfile.truncate(44)
    upload.tempfile.rewind
    original_blobs = ActiveStorage::Blob.count
    expect { received }.to raise_error(JrcContactCenter::OperationError, 'institutional_audio_invalid_codec')
    expect(JrcContactCenter::AudioAsset.where(account: account)).to be_empty
    expect(JrcContactCenter::AudioVersion.where(account: account)).to be_empty
    expect(JrcContactCenter::AudioInspection.where(account: account)).to be_empty
    expect(Audited.audit_class.where(associated: account, auditable_type: 'JrcContactCenter::AudioVersion')).to be_empty
    expect(ActiveStorage::Blob.count).to eq(original_blobs)
  end

  it 'rejects the harmless synthetic scanner marker and compensates only the newly staged bytes' do
    upload.tempfile.seek(bytes.bytesize - 1)
    upload.tempfile.write("\1")
    upload.tempfile.rewind
    original_blobs = ActiveStorage::Blob.count
    expect { received }.to raise_error(JrcContactCenter::OperationError, 'institutional_audio_unsafe_file')
    expect(JrcContactCenter::AudioAsset.where(account: account)).to be_empty
    expect(JrcContactCenter::AudioVersion.where(account: account)).to be_empty
    expect(JrcContactCenter::AudioInspection.where(account: account)).to be_empty
    expect(ActiveStorage::Blob.count).to eq(original_blobs)
  end

  it 'fails closed with an explicit unavailable response when the scanner is not configured' do
    original_blobs = ActiveStorage::Blob.count
    with_modified_env JRC_CC_AUDIO_CLAMAV_SOCKET: nil do
      expect { received }.to raise_error(JrcContactCenter::OperationError) do |error|
        expect([error.code, error.status]).to eq(['institutional_audio_inspection_unavailable', :service_unavailable])
      end
    end
    expect(JrcContactCenter::AudioAsset.where(account: account)).to be_empty
    expect(JrcContactCenter::AudioInspection.where(account: account)).to be_empty
    expect(ActiveStorage::Blob.count).to eq(original_blobs)
  end

  it 'preserves a previously accepted version and proof after a rejected replacement' do
    original = received
    original_proof = access.inspections(original).sole
    expected = JrcContactCenter::AudioAssetRevision.token(original.audio_asset, version: original)
    original_blobs = ActiveStorage::Blob.count
    upload.tempfile.truncate(44)
    upload.tempfile.rewind
    expect do
      service.replace!(asset_id: original.audio_asset_id, file: upload, key: 'synthetic-rejected-replacement-001', expected: expected)
    end.to raise_error(JrcContactCenter::OperationError, 'institutional_audio_invalid_codec')
    expect(access.versions(original.audio_asset).pluck(:id)).to eq([original.id])
    expect(access.inspections(original).pluck(:id)).to eq([original_proof.id])
    expect(original.reload.blob.download).to eq(bytes)
    expect(ActiveStorage::Blob.count).to eq(original_blobs)
  end

  it 'rolls back the asset and version if the mandatory initial observation audit fails' do
    allow(JrcContactCenter::ConfigurationAudit).to receive(:write!).and_wrap_original do |original, record, **values|
      raise ActiveRecord::RecordInvalid, record if record.is_a?(JrcContactCenter::AudioInspection)

      original.call(record, **values)
    end
    original_blobs = ActiveStorage::Blob.count
    expect { received }.to raise_error(ActiveRecord::RecordInvalid)
    expect(JrcContactCenter::AudioAsset.where(account: account)).to be_empty
    expect(JrcContactCenter::AudioVersion.where(account: account)).to be_empty
    expect(JrcContactCenter::AudioInspection.where(account: account)).to be_empty
    expect(ActiveStorage::Blob.count).to eq(original_blobs)
  end

  it 'replays the accepted exact receipt without rescanning, duplicating history or requiring a now unavailable tool' do
    original = received
    proof = access.inspections(original).sole
    with_modified_env JRC_CC_AUDIO_CLAMAV_SOCKET: nil do
      expect(JrcContactCenter::AudioSafetyObservation).not_to receive(:new)
      repeated = service.create!(unit_id: unit.id, attributes: attributes, file: upload, key: key)
      expect(repeated.id).to eq(original.id)
    end
    expect(access.inspections(original).pluck(:id)).to eq([proof.id])
    expect(proof.reload.ready?).to be(true)
    expect(original.reload.blob.download).to eq(bytes)
  end

  it 'keeps a historical unverified receipt immutable on replay without pretending it passed the new admission check' do
    legacy = JrcContactCenter::SyntheticLegacyAudioReceipt.new(access: access)
    historical = legacy.create!(unit_id: unit.id, attributes: attributes, file: upload, key: key)
    with_modified_env JRC_CC_AUDIO_CLAMAV_SOCKET: nil do
      expect(service.create!(unit_id: unit.id, attributes: attributes, file: upload, key: key).id).to eq(historical.id)
    end
    expect(access.inspections(historical)).to be_empty
    expect do
      JrcContactCenter::AudioBytes.new(access: access).call(asset_id: historical.audio_asset_id, version_id: historical.id)
    end.to raise_error(JrcContactCenter::OperationError, 'institutional_audio_not_verified')
    expect(historical.reload.blob.download).to eq(bytes)
  end
end
