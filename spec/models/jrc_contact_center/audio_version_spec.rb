require 'rails_helper'

RSpec.describe JrcContactCenter::AudioVersion do
  include_context 'with an institutional audio receipt'

  let(:receipt) do
    JrcContactCenter::AudioUploads.new(access: JrcContactCenter::AudioLibraryAccess.new(context: context))
                                  .create!(unit_id: unit.id, attributes: { name: 'SYNTHETIC immutable audio' }, file: upload, key: key)
  end

  it 'refuses model-level changes and deletion of an accepted exact version' do
    original = receipt
    expect { original.update!(file_name: 'SYNTHETIC changed.wav') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { original.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect(original.reload.file_name).to eq('SYNTHETIC.wav')
  end

  it 'protects accepted version history from SQL bulk update and delete' do
    original = receipt
    expect do
      described_class.transaction(requires_new: true) do
        described_class.connection.execute("UPDATE jrc_contact_center_audio_versions SET number = 7 WHERE id = #{original.id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /versions are immutable/)
    expect do
      described_class.transaction(requires_new: true) { described_class.where(id: original.id).delete_all }
    end.to raise_error(ActiveRecord::StatementInvalid, /versions are immutable/)
    expect(original.reload.number).to eq(1)
  end

  it 'preserves referenced blob identity and refuses removal of its private marker' do
    original = receipt
    expect do
      ActiveStorage::Blob.transaction(requires_new: true) do
        ActiveStorage::Blob.connection.execute("UPDATE active_storage_blobs SET metadata = '{}' WHERE id = #{original.blob_id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /storage identity is immutable/)
    expect do
      ActiveStorage::Blob.transaction(requires_new: true) { ActiveStorage::Blob.where(id: original.blob_id).delete_all }
    end.to raise_error(ActiveRecord::StatementInvalid, /historical bytes are protected/)
    expect(original.reload.blob.download).to eq(bytes)
  end

  it 'cannot rebind an institutional blob as a generic public attachment' do
    original = receipt
    contact = create(:contact, account: account)
    expect do
      ActiveStorage::Attachment.transaction(requires_new: true) do
        ActiveStorage::Attachment.create!(blob: original.blob, record: contact, name: 'avatar')
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /generic attachment owner/)
    expect(ActiveStorage::Attachment.where(blob: original.blob)).to be_empty
  end

  it 'prevents even a raw SQL origin move into another existing native unit' do
    asset = receipt.audio_asset
    expect do
      asset.class.transaction(requires_new: true) do
        asset.class.connection.execute("UPDATE jrc_contact_center_audio_assets SET unit_id = #{units.last.id} WHERE id = #{asset.id}")
      end
    end.to raise_error(ActiveRecord::StatementInvalid, /origin is immutable/)
    expect(asset.reload.unit_id).to eq(unit.id)
  end

  it 'does not let private-blob compensation remove an already committed version' do
    original = receipt
    JrcContactCenter::PrivateAudioBlob.clean_uncommitted(original.blob)
    expect(original.reload.blob.download).to eq(bytes)
    expect(ActiveStorage::Blob.exists?(original.blob_id)).to be(true)
  end

  it 'enforces a single historical owner for each exact stored blob even through SQL insertion' do
    original = receipt
    attributes = original.attributes.except('id').merge('number' => 2, 'idempotency_key' => 'synthetic-audio-request-0002')
    connection = described_class.connection
    columns = attributes.keys.map { |name| connection.quote_column_name(name) }.join(', ')
    values = attributes.values.map { |value| connection.quote(value) }.join(', ')
    expect do
      described_class.transaction(requires_new: true) do
        connection.execute("INSERT INTO jrc_contact_center_audio_versions (#{columns}) VALUES (#{values})")
      end
    end.to raise_error(ActiveRecord::RecordNotUnique)
    expect(described_class.where(account: account).count).to eq(1)
  end
end
