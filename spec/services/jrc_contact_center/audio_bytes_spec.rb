require 'rails_helper'

# Prepared for native Linux execution; positive observations come from the real owned scanner/decoder.
RSpec.describe JrcContactCenter::AudioBytes do
  include_context 'with an institutional audio receipt'

  let(:access) { JrcContactCenter::AudioLibraryAccess.new(context: context) }
  let(:version) do
    JrcContactCenter::AudioUploads.new(access: access)
                                  .create!(unit_id: unit.id, attributes: { name: 'SYNTHETIC private preview' }, file: upload, key: key)
  end
  let(:inspection) do
    JrcContactCenter::AudioInspections.new(access: access)
                                      .create!(asset_id: version.audio_asset_id, version_id: version.id, key: 'synthetic-preview-inspection-001')
  end

  before do
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted'
    owned &&= ENV.fetch('JRC_CC_AUDIO_CLAMAV_SOCKET', '').start_with?('/run/jrc-cc-audio-')
    raise 'Exclusively owned native preview verification required' unless owned
  end

  it 'does not turn a private unverified receipt into byte access' do
    original = version
    expect do
      described_class.new(access: access).call(asset_id: original.audio_asset_id, version_id: original.id)
    end.to raise_error(JrcContactCenter::OperationError) { |error| expect(error.code).to eq('institutional_audio_not_verified') }
    expect(original.reload.blob.download).to eq(bytes)
    expect(JrcContactCenter::AudioInspection.where(audio_version: original)).to be_empty
  end

  it 'returns only the exact bytes proven by the real native observation and rehashed in the returned buffer' do
    proof = inspection
    expect(proof.ready?).to be(true)
    result = described_class.new(access: access).call(asset_id: version.audio_asset_id, version_id: version.id)
    expect(result.bytes).to eq(bytes)
    expect(Digest::SHA256.hexdigest(result.bytes)).to eq(version.sha256)
    expect(result).to have_attributes(unit_id: unit.id.to_s, version_id: version.id.to_s, content_type: 'audio/wav', file_name: 'SYNTHETIC.wav')
    expect(result.members).not_to include(:blob_id, :key, :signed_id, :url, :idempotency_key)
  end

  it 'does not reuse an older clean observation when the current attempt is unavailable' do
    original = inspection
    expect(original.ready?).to be(true)
    with_modified_env JRC_CC_AUDIO_CLAMAV_SOCKET: nil do
      later = JrcContactCenter::AudioInspections.new(access: access).create!(
        asset_id: version.audio_asset_id, version_id: version.id, key: 'synthetic-preview-inspection-002'
      )
      expect(later.ready?).to be(false)
    end
    expect do
      described_class.new(access: access).call(asset_id: version.audio_asset_id, version_id: version.id)
    end.to raise_error(JrcContactCenter::OperationError) { |error| expect(error.code).to eq('institutional_audio_not_verified') }
    expect(original.reload.ready?).to be(true)
  end

  it 'rejects corrupted native storage rather than trusting an earlier technical receipt' do
    proof = inspection
    expect(proof.ready?).to be(true)
    version.blob.service.upload(version.blob.key, StringIO.new('SYNTHETIC corrupted owned preview bytes'))
    expect do
      described_class.new(access: access).call(asset_id: version.audio_asset_id, version_id: version.id)
    end.to raise_error(JrcContactCenter::OperationError) { |error| expect(error.code).to eq('institutional_audio_integrity_failed') }
    expect(version.reload.sha256).to eq(Digest::SHA256.hexdigest(bytes))
  end

  it 'rechecks the current profile after native file IO and withholds the read buffer after a withdrawal' do
    proof = inspection
    expect(proof.ready?).to be(true)
    service = described_class.new(access: access)
    allow(service).to receive(:read_bytes).and_wrap_original do |original, *arguments|
      buffer = original.call(*arguments)
      member.custom_role.update!(permissions: %w[jrc_contact_center_view])
      buffer
    end
    expect { service.call(asset_id: version.audio_asset_id, version_id: version.id) }.to raise_error(Pundit::NotAuthorizedError)
    expect(version.reload.blob.download).to eq(bytes)
  end

  it 'does not use a previous proof when another observation is committed during native read IO' do
    proof = inspection
    expect(proof.ready?).to be(true)
    service = described_class.new(access: access)
    allow(service).to receive(:read_bytes).and_wrap_original do |original, *arguments|
      buffer = original.call(*arguments)
      with_modified_env JRC_CC_AUDIO_CLAMAV_SOCKET: nil do
        JrcContactCenter::AudioInspections.new(access: access)
                                          .create!(asset_id: version.audio_asset_id, version_id: version.id, key: 'synthetic-preview-inspection-002')
      end
      buffer
    end
    expect do
      service.call(asset_id: version.audio_asset_id, version_id: version.id)
    end.to raise_error(JrcContactCenter::OperationError) { |error| expect(error.code).to eq('institutional_audio_not_verified') }
    expect(proof.reload.ready?).to be(true)
  end

  it 'rechecks native unit coverage after file IO instead of treating the initial version ID as an access grant' do
    expect(inspection.ready?).to be(true)
    service = described_class.new(access: access)
    allow(service).to receive(:read_bytes).and_wrap_original do |original, *arguments|
      buffer = original.call(*arguments)
      account.jrc_crm_user_business_units.where(user: actor, active: true).find_each { |grant| grant.update!(active: false) }
      buffer
    end
    expect do
      service.call(asset_id: version.audio_asset_id, version_id: version.id)
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect(version.reload.blob.download).to eq(bytes)
  end

  it 'requires a new client review even when a later ready observation replaces the selected proof during IO' do
    original_proof = inspection
    expect(original_proof.ready?).to be(true)
    service = described_class.new(access: access)
    allow(service).to receive(:read_bytes).and_wrap_original do |original, *arguments|
      buffer = original.call(*arguments)
      JrcContactCenter::AudioInspections.new(access: access).create!(
        asset_id: version.audio_asset_id, version_id: version.id, key: 'synthetic-preview-inspection-003'
      )
      buffer
    end
    expect do
      service.call(asset_id: version.audio_asset_id, version_id: version.id)
    end.to raise_error(JrcContactCenter::OperationError) { |error| expect(error.code).to eq('institutional_audio_inspection_changed') }
    expect(access.inspections(version).order(:attempt).map(&:ready?)).to eq([true, true])
  end

  it 'withholds the result on an audit-write failure and preserves the request actor context' do
    expect(inspection.ready?).to be(true)
    previous = Current.user
    allow(JrcContactCenter::ConfigurationAudit).to receive(:write_audio_read!).and_raise(ActiveRecord::RecordNotSaved, 'SYNTHETIC audit failure')
    expect do
      described_class.new(access: access).call(asset_id: version.audio_asset_id, version_id: version.id)
    end.to raise_error(ActiveRecord::RecordNotSaved)
    expect(Current.user).to eq(previous)
    expect(Audited.audit_class.where(auditable: version, action: 'read')).to be_empty
    expect(version.reload.blob.download).to eq(bytes)
  end
end
