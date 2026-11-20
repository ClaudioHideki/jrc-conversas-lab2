require 'rails_helper'

# Real owned ClamAV/FFmpeg, synthetic definition DB. No final library record may exist at this point.
RSpec.describe JrcContactCenter::AudioSafetyObservation, 'before final persistence' do
  include_context 'with an institutional audio receipt'

  let(:access) { JrcContactCenter::AudioLibraryAccess.new(context: context) }
  let(:input) { JrcContactCenter::AudioFileInput.new(file: upload) }
  let(:blob) do
    JrcContactCenter::PrivateAudioBlob.upload(file: input.file, filename: input.filename, content_type: input.content_type)
  end
  let(:observer) { described_class.new(access: access) }

  before do
    owned = ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' && ENV.fetch('JRC_CC_AUDIO_CLAMAV_SOCKET', '').start_with?('/run/jrc-cc-audio-')
    raise 'Owned native synthetic scanner required before final audio persistence' unless Rails.env.test? && owned
  end

  after { JrcContactCenter::PrivateAudioBlob.clean_uncommitted(blob) }

  it 'verifies actual staged bytes without creating a final asset, immutable version or inspection row' do
    result = observer.receive!(unit_id: unit.id, blob: blob, input: input)
    expect(result).to include(state: 'clean', probe_state: 'valid', observed_sha256: input.sha256)
    expect(result.fetch(:metadata)).to include('codec' => 'pcm_s16le', 'duration_ms' => 1)
    expect(JrcContactCenter::AudioAsset.where(account: account)).to be_empty
    expect(JrcContactCenter::AudioVersion.where(account: account)).to be_empty
    expect(JrcContactCenter::AudioInspection.where(account: account)).to be_empty
    expect(blob.download).to eq(bytes)
  end

  it 'rejects a genuinely clean header without decodable samples before any final record can be created' do
    upload.tempfile.truncate(44)
    upload.tempfile.rewind
    expect do
      observer.receive!(unit_id: unit.id, blob: blob, input: input)
    end.to raise_error(JrcContactCenter::OperationError) { |error| expect(error.code).to eq('institutional_audio_invalid_codec') }
    expect(JrcContactCenter::AudioVersion.where(account: account)).to be_empty
  end

  it 'rejects the harmless synthetic marker with the real scanner without persisting a final version' do
    upload.tempfile.seek(bytes.bytesize - 1)
    upload.tempfile.write("\1")
    upload.tempfile.rewind
    expect do
      observer.receive!(unit_id: unit.id, blob: blob, input: input)
    end.to raise_error(JrcContactCenter::OperationError) { |error| expect(error.code).to eq('institutional_audio_unsafe_file') }
    expect(JrcContactCenter::AudioVersion.where(account: account)).to be_empty
  end

  it 'does not treat an unavailable scanner as permission to persist the staged file' do
    source = blob
    with_modified_env JRC_CC_AUDIO_CLAMAV_SOCKET: nil do
      expect do
        observer.receive!(unit_id: unit.id, blob: source, input: input)
      end.to raise_error(JrcContactCenter::OperationError) { |error| expect(error.code).to eq('institutional_audio_inspection_unavailable') }
    end
    expect(JrcContactCenter::AudioAsset.where(account: account)).to be_empty
  end

  it 'rechecks current authority after actual native verification rather than committing a prior profile decision' do
    source = blob
    allow(observer).to receive(:inspect_bytes).and_wrap_original do |original, *arguments|
      result = original.call(*arguments)
      member.custom_role.update!(permissions: %w[jrc_contact_center_view])
      result
    end
    expect do
      observer.receive!(unit_id: unit.id, blob: source, input: input)
    end.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcContactCenter::AudioVersion.where(account: account)).to be_empty
  end

  it 'does not validate a staged file for a unit outside the current native corporate coverage' do
    expect do
      observer.receive!(unit_id: units.last.id, blob: blob, input: input)
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcContactCenter::AudioVersion.where(account: account)).to be_empty
  end
end
