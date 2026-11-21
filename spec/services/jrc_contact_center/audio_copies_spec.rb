require 'rails_helper'

RSpec.describe JrcContactCenter::AudioCopies do
  include_context 'with an institutional audio receipt'

  let(:access) { JrcContactCenter::AudioLibraryAccess.new(context: context) }
  let(:source_version) do
    JrcContactCenter::AudioUploads.new(access: access)
                                  .create!(unit_id: unit.id, attributes: { name: 'SYNTHETIC original' }, file: upload, key: key)
  end
  let(:copies) { described_class.new(access: access) }
  let(:copy_request) do
    asset = source_version.audio_asset.reload
    { asset_id: asset.id.to_s, version_id: source_version.id.to_s, attributes: { 'name' => 'SYNTHETIC reviewed copy' },
      key: 'synthetic-copy-request-0001', expected: JrcContactCenter::AudioAssetRevision.token(asset, version: source_version) }
  end

  it 'creates its own identity and blob with exact verified bytes and a new native inspection while preserving the original' do
    request = copy_request
    original = source_version.reload.attributes
    duplicate = copies.call(**request)
    proof = duplicate.reload.latest_inspection
    audit = Audited.audit_class.where(auditable: duplicate, action: 'copy').sole
    expect(duplicate.audio_asset_id).not_to eq(source_version.audio_asset_id)
    expect(duplicate.blob_id).not_to eq(source_version.blob_id)
    expect([duplicate.number, duplicate.source_kind, duplicate.sha256]).to eq([1, source_version.source_kind, source_version.sha256])
    expect(duplicate.blob.download).to eq(bytes)
    expect([proof.audio_version_id, proof.ready?]).to eq([duplicate.id, true])
    expect(audit.audited_changes.fetch('audio_copy')).to eq('source_asset_id' => request.fetch(:asset_id),
                                                         'source_version_id' => request.fetch(:version_id),
                                                         'source_sha256' => source_version.sha256)
    expect(source_version.reload.attributes).to eq(original)
  end

  it 'replays the exact same reviewed operation without creating blobs or releasing source bytes again' do
    first = copies.call(**copy_request)
    counts = [JrcContactCenter::AudioAsset.count, JrcContactCenter::AudioVersion.count, ActiveStorage::Blob.count]
    allow(JrcContactCenter::AudioBytes).to receive(:new).and_raise('A known replay must not release source bytes again')
    second = described_class.new(access: access).call(**copy_request)
    expect(second.id).to eq(first.id)
    expect([JrcContactCenter::AudioAsset.count, JrcContactCenter::AudioVersion.count, ActiveStorage::Blob.count]).to eq(counts)
    expect(Audited.audit_class.where(auditable: first, action: 'copy').count).to eq(1)
  end

  it 'rejects a reused key with different destination attributes instead of creating a second copy' do
    first = copies.call(**copy_request)
    changed = copy_request.merge(attributes: { 'name' => 'SYNTHETIC changed request' })
    expect { described_class.new(access: access).call(**changed) }
      .to raise_error(JrcContactCenter::OperationError, 'institutional_audio_upload_key_conflict')
    expect(JrcContactCenter::AudioVersion.where(account: account).count).to eq(2)
    expect(first.audio_asset.reload.name).to eq('SYNTHETIC reviewed copy')
  end

  it 'does not alias an existing upload receipt as a copy when the caller reuses the original key' do
    request = copy_request.merge(key: key)
    expect { copies.call(**request) }.to raise_error(JrcContactCenter::OperationError, 'institutional_audio_upload_key_conflict')
    expect(JrcContactCenter::AudioVersion.where(account: account).count).to eq(1)
    expect(Audited.audit_class.where(auditable: source_version, action: 'copy')).not_to exist
  end

  it 'binds the exact version identity even when a newer source has identical file bytes' do
    request = copy_request
    first = copies.call(**request)
    newer = JrcContactCenter::AudioUploads.new(access: access).replace!(
      asset_id: request.fetch(:asset_id), file: upload, key: 'synthetic-original-next-version-0002', expected: request.fetch(:expected)
    )
    expected = JrcContactCenter::AudioAssetRevision.token(newer.audio_asset, version: newer)
    expect(newer.sha256).to eq(first.sha256)
    expect { copies.call(**request.merge(version_id: newer.id.to_s, expected: expected)) }
      .to raise_error(JrcContactCenter::OperationError, 'institutional_audio_upload_key_conflict')
    expect(JrcContactCenter::AudioAsset.where(account: account).count).to eq(2)
    expect(source_version.reload.blob.download).to eq(bytes)
  end

  it 'rejects a source asset in another unit before creating or reading any bytes' do
    request = copy_request
    hidden = JrcContactCenter::AudioAsset.create!(account: account, unit: units.last, name: 'SYNTHETIC denied source')
    expect { copies.call(**request.merge(asset_id: hidden.id.to_s)) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcContactCenter::AudioVersion.where(account: account).count).to eq(1)
  end

  it 'rejects a genuine version ID attached to the wrong native source asset' do
    request = copy_request
    other = JrcContactCenter::AudioAsset.create!(account: account, unit: unit, name: 'SYNTHETIC different source')
    expect { copies.call(**request.merge(asset_id: other.id.to_s)) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcContactCenter::AudioVersion.where(account: account).count).to eq(1)
  end

  it 'refuses a destination folder in another unit while keeping the original identity and bytes' do
    request = copy_request
    hidden = JrcContactCenter::AudioFolder.create!(account: account, unit: units.last, name: 'SYNTHETIC denied folder')
    request[:attributes] = { 'name' => 'SYNTHETIC copy', 'folder_id' => hidden.id.to_s }
    expect { copies.call(**request) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcContactCenter::AudioVersion.where(account: account).count).to eq(1)
    expect(source_version.blob.download).to eq(bytes)
  end

  it 'does not treat telephone-recording listening rights as permission to duplicate an institutional file' do
    request = copy_request
    member.custom_role.update!(permissions: %w[jrc_contact_center_view jrc_contact_center_recordings_view jrc_contact_center_recordings_listen])
    expect { copies.call(**request) }.to raise_error(Pundit::NotAuthorizedError)
    expect(JrcContactCenter::AudioVersion.where(account: account).count).to eq(1)
  end

  it 'requires the actual source revision after a rename without silently selecting a different version' do
    request = copy_request
    source_version.audio_asset.update!(name: 'SYNTHETIC concurrently renamed original')
    expect { copies.call(**request) }.to raise_error(JrcContactCenter::OperationError, 'stale_configuration_revision')
    expect(JrcContactCenter::AudioVersion.where(account: account).count).to eq(1)
  end

  it 'requires the source precondition before creating any new identity' do
    request = copy_request.merge(expected: nil)
    expect { copies.call(**request) }.to raise_error(JrcContactCenter::OperationError, 'configuration_revision_required')
    expect(JrcContactCenter::AudioVersion.where(account: account).count).to eq(1)
  end

  it 'rechecks the exact source revision after scanning and rolls back only the new staged copy on a race' do
    request = copy_request
    initial = [JrcContactCenter::AudioAsset.count, JrcContactCenter::AudioVersion.count, ActiveStorage::Blob.count]
    allow(copies).to receive(:inspect_staged!).and_wrap_original do |original, *arguments|
      observation = original.call(*arguments)
      source_version.audio_asset.update!(name: 'SYNTHETIC renamed during copy inspection')
      observation
    end
    expect { copies.call(**request) }.to raise_error(JrcContactCenter::OperationError, 'stale_configuration_revision')
    expect([JrcContactCenter::AudioAsset.count, JrcContactCenter::AudioVersion.count, ActiveStorage::Blob.count]).to eq(initial)
    expect(source_version.blob.download).to eq(bytes)
  end

  it 'reauthorizes the current profile after scanning without retaining staged bytes after permission withdrawal' do
    request = copy_request
    initial = [JrcContactCenter::AudioAsset.count, JrcContactCenter::AudioVersion.count, ActiveStorage::Blob.count]
    allow(copies).to receive(:inspect_staged!).and_wrap_original do |original, *arguments|
      observation = original.call(*arguments)
      member.custom_role.update!(permissions: %w[jrc_contact_center_view])
      observation
    end
    expect { copies.call(**request) }.to raise_error(Pundit::NotAuthorizedError)
    expect([JrcContactCenter::AudioAsset.count, JrcContactCenter::AudioVersion.count, ActiveStorage::Blob.count]).to eq(initial)
    expect(source_version.blob.download).to eq(bytes)
  end

  it 'does not inherit source approval when the mandatory new inspection is unavailable' do
    request = copy_request
    expect(source_version.reload.latest_inspection).to be_ready
    with_modified_env JRC_CC_AUDIO_CLAMAV_SOCKET: nil do
      expect { copies.call(**request) }.to raise_error(JrcContactCenter::OperationError, 'institutional_audio_inspection_unavailable')
    end
    expect(JrcContactCenter::AudioVersion.where(account: account).count).to eq(1)
    expect(ActiveStorage::Blob.where(id: source_version.blob_id)).to exist
    expect(Audited.audit_class.where(auditable_type: source_version.class.name, action: 'copy')).not_to exist
  end

  it 'rolls back the new identity, version and blob when recording the native copy audit fails' do
    request = copy_request
    initial = [JrcContactCenter::AudioAsset.count, JrcContactCenter::AudioVersion.count, ActiveStorage::Blob.count]
    allow(Audited.audit_class).to receive(:create!).and_wrap_original do |original, **attributes|
      raise 'SYNTHETIC copy audit refusal' if attributes[:action] == 'copy'

      original.call(**attributes)
    end
    expect { copies.call(**request) }.to raise_error(RuntimeError, 'SYNTHETIC copy audit refusal')
    expect([JrcContactCenter::AudioAsset.count, JrcContactCenter::AudioVersion.count, ActiveStorage::Blob.count]).to eq(initial)
    expect(source_version.blob.download).to eq(bytes)
  end
end
