require 'rails_helper'

RSpec.describe 'Concurrent imported media rollback compensation', :sd_concurrency do
  self.use_transactional_tests = false
  include JrcServiceDeskConcurrency
  include_context 'JRC migration media fixtures'

  after do
    # Only this committed fixture; never reset a shared database or storage root.
    project.reload.attachments.each(&:purge)
    JrcMigrations::MediaObject.where(account_id: account.id).find_each do |media|
      ActiveStorage::Blob.where(key: media.storage_key, service_name: media.service_name).find_each(&:purge)
      ActiveStorage::Blob.services.fetch(media.service_name).delete(media.storage_key)
    end
    JrcMigrations::Mapping.where(account_id: account.id).delete_all
    JrcMigrations::Item.where(account_id: account.id).delete_all
    JrcMigrations::Batch.where(account_id: account.id).delete_all
    project.reload.destroy!
    account.destroy!
    admin.destroy!
  end

  it 'claims rollback compensation before a retry can upload another Blob to the same key' do
    preview_media
    batch_id, user_id = batch.id, admin.id
    original_key = media_object.storage_key
    deleting = Queue.new
    retry_finished = Queue.new
    service = ActiveStorage::Blob.service
    allow(JrcMigrations::Event).to receive(:record!).and_wrap_original do |original, **arguments|
      if Thread.current[:rollback_import] && arguments[:action] == 'EXECUTED'
        raise IOError, 'Synthetic outer transaction rollback'
      end
      original.call(**arguments)
    end
    allow(service).to receive(:delete).and_wrap_original do |original, key|
      if Thread.current[:rollback_import] && !Thread.current[:delete_barrier_seen]
        Thread.current[:delete_barrier_seen] = true
        deleting << true
        Timeout.timeout(15) { retry_finished.pop }
      end
      original.call(key)
    end
    outcomes = concurrently([
      lambda do
        Thread.current[:rollback_import] = true
        JrcMigrations::Execute.new(batch: JrcMigrations::Batch.find(batch_id), user: User.find(user_id)).call
      end,
      lambda do
        Timeout.timeout(15) { deleting.pop }
        retry_batch = JrcMigrations::Batch.find(batch_id)
        JrcMigrations::Preview.new(batch: retry_batch, user: User.find(user_id)).call
        retry_item = retry_batch.items.reload.sole
        if retry_item.decision == 'reject' && retry_item.error_code == 'MEDIA_RECOVERY_REQUIRED'
          :retry_blocked
        else
          JrcMigrations::Execute.new(batch: retry_batch, user: User.find(user_id)).call
          :replacement_applied
        end
      ensure
        retry_finished << true
      end
    ])
    expect(outcomes.grep(IOError).size).to eq(1)
    expect(outcomes).to include(:retry_blocked)
    expect(outcomes).not_to include(:replacement_applied)
    expect(media_object.reload.status).to eq('cleaned')
    JrcMigrations::Preview.new(batch: batch.reload, user: admin).call
    expect(media_object.storage_key).not_to eq(original_key)
    blob = execute_media
    expect(blob.download).to eq(bytes)
    expect(media_object.status).to eq('attached')
  end
end
