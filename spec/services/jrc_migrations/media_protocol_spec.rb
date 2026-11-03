require 'rails_helper'

RSpec.describe 'Durable ownership of imported media' do
  include_context 'JRC migration media fixtures'

  it 'reserves an immutable new storage key in the preview without creating bytes or a Blob' do
    item = preview_media
    media = media_object
    expect(media).to have_attributes(account_id: account.id, batch_id: batch.id, item_id: item.id,
                                    status: 'planned', source_sha256: media_row['file_sha256'], byte_size: bytes.bytesize)
    expect(ActiveStorage::Blob.where(key: media.storage_key, service_name: media.service_name)).to be_empty
    expect(ActiveStorage::Blob.services.fetch(media.service_name).exist?(media.storage_key)).to be(false)
    expect { preview_media }.not_to change(JrcMigrations::MediaObject, :count)
    expect(media_object.storage_key).to eq(media.storage_key)
    original_key = media.storage_key
    expect do
      JrcMigrations::MediaObject.transaction(requires_new: true) do
        # Exercise the database ownership guard, not model readonly assignment.
        JrcMigrations::MediaObject.where(id: media.id).update_all(storage_key: SecureRandom.base58(28)) # rubocop:disable Rails/SkipsModelValidations
      end
    end.to raise_error(ActiveRecord::StatementInvalid)
    expect(media.reload.storage_key).to eq(original_key)
  end

  it 'rejects a reserved SQL row without a storage identity at the database boundary' do
    preview_media
    attributes = media_object.attributes.except('id', 'created_at', 'updated_at').merge(
      'generation' => 2, 'storage_key' => SecureRandom.base36(28), 'status' => 'reserved',
      'storage_identity' => nil, 'absence_verified_at' => nil
    )
    expect do
      JrcMigrations::MediaObject.transaction(requires_new: true) do
        JrcMigrations::MediaObject.insert_all!([attributes]) # rubocop:disable Rails/SkipsModelValidations
      end
    end.to raise_error(ActiveRecord::StatementInvalid)
  end

  it 'returns a typed preview error when recovery is requested before physical absence was verified' do
    preview_media
    attributes = media_object.attributes.except('id', 'created_at', 'updated_at').merge(
      'generation' => 2, 'storage_key' => SecureRandom.base36(28), 'status' => 'reserved', 'absence_verified_at' => nil
    )
    reservation = JrcMigrations::MediaObject.create!(attributes)
    expect do
      JrcMigrations::MediaRecovery.new(media: reservation, user: admin).call
    end.to raise_error(JrcMigrations::Error, 'MEDIA_PREVIEW_REQUIRED')
    expect(reservation.reload.status).to eq('reserved')
  end

  it 'uses the reserved key and preserves a completed attachment during recovery' do
    preview_media
    key = media_object.storage_key
    blob = execute_media
    expect(blob.key).to eq(key)
    expect(media_object).to have_attributes(status: 'attached', blob_id: blob.id)
    expect(blob.service).not_to receive(:delete)
    JrcMigrations::MediaRecovery.new(media: media_object, user: admin).call
    expect(blob.reload.download).to eq(bytes)
    expect(project.attachments_attachments.sole.blob_id).to eq(blob.id)
  end

  it 'recovers an uncommitted physical object from the ledger in a fresh service instance' do
    preview_media
    media = media_object
    service = ActiveStorage::Blob.services.fetch(media.service_name)
    service.upload(media.storage_key, StringIO.new(bytes))
    expect(ActiveStorage::Blob.where(key: media.storage_key)).to be_empty
    JrcMigrations::MediaRecovery.new(media: media.reload, user: admin).call
    expect(service.exist?(media.storage_key)).to be(false)
    expect(media.reload.status).to eq('cleaned')
    expect { JrcMigrations::MediaRecovery.new(media: media.reload, user: admin).call }.not_to raise_error
    preview_media
    expect(media_object.storage_key).not_to eq(media.storage_key)
  ensure
    service&.delete(media.storage_key) if media
  end

  it 'keeps any registered Blob with the same service and key even when it is not this batch attachment' do
    preview_media
    media = media_object
    blob = ActiveStorage::Blob.create_and_upload!(key: media.storage_key, service_name: media.service_name,
      io: StringIO.new(bytes), filename: 'registered-keep.pdf', content_type: 'application/pdf')
    expect(blob.service).not_to receive(:delete)
    JrcMigrations::MediaRecovery.new(media: media, user: admin).call
    expect(media.reload.status).to eq('kept')
    expect(blob.reload.download).to eq(bytes)
  end

  it 'persists a failed cleanup for retry and rechecks current administrator authority' do
    preview_media
    media = media_object
    service = ActiveStorage::Blob.services.fetch(media.service_name)
    service.upload(media.storage_key, StringIO.new(bytes))
    allow(service).to receive(:delete).and_raise(IOError, 'Synthetic deletion outage')
    JrcMigrations::MediaRecovery.new(media: media, user: admin).call
    expect(media.reload).to have_attributes(status: 'cleanup_required', error_code: 'ATTACHMENT_CLEANUP_REQUIRED')
    account.account_users.find_by!(user: admin).update!(role: :agent)
    expect { JrcMigrations::MediaRecovery.new(media: media, user: admin).call }.to raise_error(JrcMigrations::Error, 'MIGRATION_FORBIDDEN')
    expect(service.exist?(media.storage_key)).to be(true)
  ensure
    if service && media
      allow(service).to receive(:delete).and_call_original
      service.delete(media.storage_key)
    end
  end

  it 'preserves a remote object without a Blob and reserves a different key before the first PUT' do
    service = ActiveStorage::Blob.service
    collision = SecureRandom.base36(28)
    replacement = SecureRandom.base36(28)
    service.upload(collision, StringIO.new('Synthetic preexisting storage object'))
    allow(SecureRandom).to receive(:base36).and_call_original
    allow(SecureRandom).to receive(:base36).with(28).and_return(collision, replacement)
    preview_media
    expect(media_object.storage_key).to eq(replacement)
    execute_media
    expect(service.download(collision)).to eq('Synthetic preexisting storage object')
    expect(JrcMigrations::MediaObject.find_by!(storage_key: collision).status).to eq('kept')
  ensure
    service&.delete(collision) if collision
  end

  it 'refuses the first PUT after the configured storage destination changes' do
    preview_media
    media = media_object
    service = ActiveStorage::Blob.service
    previous_root = service.root
    changed_root = Dir.mktmpdir('jrc-migration-storage-change-')
    service.root = changed_root
    service.upload(media.storage_key, StringIO.new('Synthetic foreign storage object'))
    JrcMigrations::Execute.new(batch: batch, user: admin).call
    expect(batch.items.reload.sole).to have_attributes(status: 'failed', error_code: 'MEDIA_STORAGE_CHANGED')
    expect(service.download(media.storage_key)).to eq('Synthetic foreign storage object')
  ensure
    service.root = previous_root if service && previous_root
    FileUtils.remove_entry(changed_root) if changed_root && File.directory?(changed_root)
  end

  it 'refuses cleanup in a reconfigured storage destination even when the key has no registered Blob' do
    preview_media
    media = media_object
    service = ActiveStorage::Blob.service
    previous_root = service.root
    changed_root = Dir.mktmpdir('jrc-migration-cleanup-change-')
    service.root = changed_root
    service.upload(media.storage_key, StringIO.new('Synthetic foreign storage object'))
    expect { JrcMigrations::MediaRecovery.new(media: media, user: admin).call }.to raise_error(JrcMigrations::Error, 'MEDIA_STORAGE_CHANGED')
    expect(service.download(media.storage_key)).to eq('Synthetic foreign storage object')
  ensure
    service.root = previous_root if service && previous_root
    FileUtils.remove_entry(changed_root) if changed_root && File.directory?(changed_root)
  end

  it 'advances the scheduled sweep past the first hundred failures instead of starving subsequent reservations' do
    preview_media
    first = media_object
    first.update!(checked_at: nil)
    attributes = first.attributes.except('id', 'created_at', 'updated_at')
    100.times do |index|
      JrcMigrations::MediaObject.create!(attributes.merge('storage_key' => SecureRandom.base36(28), 'generation' => index + 2))
    end
    expect(JrcMigrations::MediaObject.where(account_id: account.id, checked_at: nil).count).to eq(101)
    last = JrcMigrations::MediaObject.where(account_id: account.id).order(:id).last!
    allow(JrcMigrations::MediaRecovery).to receive(:sweep).and_wrap_original do |original, candidate|
      raise IOError, 'Synthetic unavailable storage' unless candidate.id == last.id

      original.call(candidate)
    end
    allow(Rails.logger).to receive(:error)
    2.times { JrcMigrations::MediaRecoveryJob.perform_now }
    expect(last.reload.checked_at).to be_present
    expect(JrcMigrations::MediaObject.where(account_id: account.id, checked_at: nil)).to be_empty
  end
end
