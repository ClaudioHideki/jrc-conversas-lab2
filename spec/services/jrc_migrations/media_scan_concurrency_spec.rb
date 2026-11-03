require 'rails_helper'

RSpec.describe 'Concurrent imported media scan verdicts', :sd_concurrency do
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

  it 'rejects an older clean result after a newer infected scan committed for the same immutable bytes' do
    blob = execute_media
    item_id, user_id, blob_id = batch.items.sole.id, admin.id, blob.id
    expected_sha = Digest::SHA256.hexdigest(bytes)
    old_scan_started = Queue.new
    new_scan_committed = Queue.new
    # Only the daemon verdict/timing is replaced. MediaScan still performs both
    # physical readbacks and all real PostgreSQL source/authority checks.
    allow_any_instance_of(JrcServiceDesk::AttachmentScanner).to receive(:scan) do |_scanner, scanned_blob|
      raise 'Unexpected fixture blob' unless scanned_blob.id == blob_id

      old = Thread.current[:jrc_media_old_scan] == true
      if old
        old_scan_started << true
        Timeout.timeout(10) { new_scan_committed.pop }
      end
      { 'service_desk_scan_state' => old ? 'clean' : 'infected',
        'service_desk_scan_sha256' => expected_sha, 'service_desk_scan_adapter' => 'clamav-instream-v1',
        'service_desk_scanned_at' => Time.current.iso8601(6) }
    end
    outcomes = concurrently([
      lambda do
        Thread.current[:jrc_media_old_scan] = true
        JrcMigrations::MediaScan.new(item: JrcMigrations::Item.find(item_id), user: User.find(user_id)).call
        :stale_clean_committed
      end,
      lambda do
        Timeout.timeout(10) { old_scan_started.pop }
        JrcMigrations::MediaScan.new(item: JrcMigrations::Item.find(item_id), user: User.find(user_id)).call
        :new_infected_committed
      ensure
        new_scan_committed << true
      end
    ])
    aggregate_failures do
      expect(outcomes).to include(:new_infected_committed)
      expect(outcomes).not_to include(:stale_clean_committed)
      expect(outcomes.grep(JrcMigrations::Error).map(&:message)).to eq(['MEDIA_SCAN_CHANGED'])
      expect(blob.reload.metadata['service_desk_scan_state']).to eq('infected')
      expect(JrcServiceDesk::AttachmentScanner.clean?(blob)).to be(false)
      audits = batch.events.where(action: 'MEDIA_SCANNED')
      expect(audits.count).to eq(1)
      expect(audits.pluck(:metadata).map { |metadata| metadata['scan_state'] }).to eq(['infected'])
      expect(JrcMigrations::AttachmentStorage.sha256(blob)).to eq(expected_sha)
    end
  end
end
