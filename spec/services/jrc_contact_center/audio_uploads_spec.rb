require 'rails_helper'

RSpec.describe JrcContactCenter::AudioUploads do
  include_context 'institutional audio receipt'

  let(:access) { JrcContactCenter::AudioLibraryAccess.new(context: context) }
  let(:service) { described_class.new(access: access) }
  let(:attributes) { { name: 'SYNTHETIC private message' } }
  let(:receipt) { service.create!(unit_id: unit.id, attributes: attributes, file: upload, key: key) }

  it 'receives exact private bytes with an immutable origin and no implicit ActiveStorage attachment or provider command' do
    version = receipt
    expect(version).to have_attributes(number: 1, account_id: account.id, unit_id: unit.id, created_by_id: actor.id,
                                      sha256: Digest::SHA256.hexdigest(bytes), byte_size: bytes.bytesize, source_kind: 'user_upload')
    expect(version.blob.download).to eq(bytes)
    expect(version.blob.metadata).to include(JrcContactCenter::PrivateAudioBlob::MARKER => true)
    expect(ActiveStorage::Attachment.where(blob: version.blob)).to be_empty
    expect(JrcContactCenter::Command.where(account: account)).to be_empty
    expect(version.audio_asset.name).to eq(attributes[:name])
  end

  it 'replays the same uncertain submission without another asset, blob or version' do
    original = receipt
    blob_count = ActiveStorage::Blob.count
    repeated = service.create!(unit_id: unit.id.to_s, attributes: attributes, file: upload, key: key)
    expect(repeated.id).to eq(original.id)
    expect(JrcContactCenter::AudioAsset.where(account: account).count).to eq(1)
    expect(JrcContactCenter::AudioVersion.where(account: account).count).to eq(1)
    expect(ActiveStorage::Blob.count).to eq(blob_count)
  end

  it 'rejects changed content under an already accepted key rather than duplicating or replacing history' do
    original = receipt
    expect do
      service.create!(unit_id: unit.id, attributes: { name: 'SYNTHETIC changed' }, file: upload, key: key)
    end.to raise_error(JrcContactCenter::OperationError, 'institutional_audio_upload_key_conflict')
    expect(original.reload.audio_asset.name).to eq(attributes[:name])
    expect(JrcContactCenter::AudioVersion.where(account: account).count).to eq(1)
  end

  it 'appends a reviewed exact version and preserves the prior bytes independently of the current name' do
    first = receipt
    asset = first.audio_asset
    expected = JrcContactCenter::AudioAssetRevision.token(asset, version: first)
    second = service.replace!(asset_id: asset.id, file: upload, key: 'synthetic-audio-request-0002', expected: expected)
    expect(second).to have_attributes(number: 2, audio_asset_id: asset.id, unit_id: unit.id)
    expect(second.blob_id).not_to eq(first.blob_id)
    expect(first.reload.blob.download).to eq(bytes)
    expect(JrcContactCenter::AudioAssetRevision.token(asset.reload, version: second)).not_to eq(expected)
  end

  it 'rejects a stale replacement before staging another blob and permits an exact accepted replay after CAS changes' do
    first = receipt
    expected = JrcContactCenter::AudioAssetRevision.token(first.audio_asset, version: first)
    second = service.replace!(asset_id: first.audio_asset_id, file: upload, key: 'synthetic-audio-request-0002', expected: expected)
    replay = service.replace!(asset_id: first.audio_asset_id, file: upload, key: 'synthetic-audio-request-0002', expected: expected)
    expect(replay.id).to eq(second.id)
    blob_count = ActiveStorage::Blob.count
    expect do
      service.replace!(asset_id: first.audio_asset_id, file: upload, key: 'synthetic-audio-request-0003', expected: expected)
    end.to raise_error(JrcContactCenter::OperationError, 'stale_configuration_revision')
    expect(ActiveStorage::Blob.count).to eq(blob_count)
  end

  it 'does not stage bytes for a unit outside current native coverage' do
    expect(JrcContactCenter::PrivateAudioBlob).not_to receive(:upload)
    expect do
      service.create!(unit_id: units.last.id, attributes: attributes, file: upload, key: key)
    end.to raise_error(ActiveRecord::RecordNotFound)
    expect(JrcContactCenter::AudioVersion.where(account: account)).to be_empty
  end

  it 'compensates only its newly staged bytes when mandatory audit rejects the atomic receipt' do
    allow(JrcContactCenter::ConfigurationAudit).to receive(:write!).and_wrap_original do |original, record, **values|
      raise ActiveRecord::RecordInvalid, record if record.is_a?(JrcContactCenter::AudioVersion)

      original.call(record, **values)
    end
    before = ActiveStorage::Blob.count
    expect { receipt }.to raise_error(ActiveRecord::RecordInvalid)
    expect(ActiveStorage::Blob.count).to eq(before)
    expect(JrcContactCenter::AudioAsset.where(account: account)).to be_empty
    expect(JrcContactCenter::AudioVersion.where(account: account)).to be_empty
  end

  it 'rechecks the current role after staging and rolls back bytes without using the earlier permission snapshot' do
    allow(JrcContactCenter::PrivateAudioBlob).to receive(:upload).and_wrap_original do |original, **values|
      stored = original.call(**values)
      member.custom_role.update!(permissions: %w[jrc_contact_center_view])
      stored
    end
    before = ActiveStorage::Blob.count
    expect { receipt }.to raise_error(Pundit::NotAuthorizedError)
    expect(ActiveStorage::Blob.count).to eq(before)
    expect(JrcContactCenter::AudioVersion.where(account: account)).to be_empty
  end

  it 'keeps accepted history when the creator loses their account membership' do
    original = receipt
    member.destroy!
    expect(original.reload.created_by_id).to eq(actor.id)
    expect(original.blob.download).to eq(bytes)
    expect { service.create!(unit_id: unit.id, attributes: attributes, file: upload, key: key) }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'does not persist a file if its native corporate unit coverage changes while the bytes are staged' do
    allow(JrcContactCenter::PrivateAudioBlob).to receive(:upload).and_wrap_original do |original, **values|
      stored = original.call(**values)
      account.jrc_crm_user_business_units.find_by!(user: actor).update!(business_unit_id: units.last.settings.fetch('business_unit_id'))
      stored
    end
    before = ActiveStorage::Blob.count
    expect { receipt }.to raise_error(ActiveRecord::RecordNotFound)
    expect(ActiveStorage::Blob.count).to eq(before)
    expect(JrcContactCenter::AudioVersion.where(account: account)).to be_empty
  end

  it 'preserves a failed upload as a failure and compensates only the staged blob created by that attempt' do
    allow(ActiveStorage::Blob).to receive(:create_after_unfurling!).and_wrap_original do |original, **values|
      stored = original.call(**values)
      allow(stored).to receive(:upload_without_unfurling).and_raise(IOError, 'synthetic storage failure')
      stored
    end
    before = ActiveStorage::Blob.count
    expect { receipt }.to raise_error(IOError, 'synthetic storage failure')
    expect(ActiveStorage::Blob.count).to eq(before)
    expect(JrcContactCenter::AudioVersion.where(account: account)).to be_empty
  end
end
