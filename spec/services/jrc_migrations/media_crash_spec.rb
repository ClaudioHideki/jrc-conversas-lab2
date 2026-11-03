require 'rails_helper'

RSpec.describe 'Imported media recovery after an actual worker process dies', :sd_concurrency do
  self.use_transactional_tests = false
  include JrcServiceDeskConcurrency
  include_context 'JRC migration media fixtures'

  after do
    # Only this committed fixture, including a possible orphan from the killed worker.
    if defined?(JrcMigrations::MediaObject)
      JrcMigrations::MediaObject.where(account_id: account.id).find_each do |media|
        ActiveStorage::Blob.where(key: media.storage_key, service_name: media.service_name).find_each(&:purge)
        ActiveStorage::Blob.services.fetch(media.service_name).delete(media.storage_key)
      end
    end
    project.attachments.each(&:purge)
    JrcMigrations::Mapping.where(account_id: account.id).delete_all
    JrcMigrations::Item.where(account_id: account.id).delete_all
    JrcMigrations::Batch.where(account_id: account.id).delete_all
    project.reload.destroy!
    account.destroy!
    admin.destroy!
  end

  it 'finds the pre-upload ledger and removes orphan bytes after SIGKILL bypasses every Ruby rollback callback' do
    preview_media
    media = media_object
    ledger_id = media.id
    batch_id = batch.id
    admin_id = admin.id
    reader, writer = IO.pipe
    # The fixture is committed. Never share a live PostgreSQL socket across fork.
    ActiveRecord::Base.connection_pool.disconnect!
    worker_pid = fork do
      reader.close
      allow_any_instance_of(ActiveStorage::Blob).to receive(:upload).and_wrap_original do |original, *args, **kwargs|
        original.call(*args, **kwargs)
        writer.write('uploaded')
        writer.close
        Process.kill('KILL', Process.pid)
      end
      JrcMigrations::Execute.new(batch: JrcMigrations::Batch.find(batch_id), user: User.find(admin_id)).call
      exit! 99
    end
    writer.close
    expect(Timeout.timeout(20) { reader.read }).to eq('uploaded')
    _, status = Timeout.timeout(20) { Process.wait2(worker_pid) }
    worker_pid = nil # Never signal an already reaped PID that the OS could reuse.
    expect(status).to be_signaled
    expect(status.termsig).to eq(Signal.list.fetch('KILL'))
    media = JrcMigrations::MediaObject.find(ledger_id)
    expect(media.status).to eq('planned')
    expect(ActiveStorage::Blob.where(key: media.storage_key, service_name: media.service_name)).to be_empty
    service = ActiveStorage::Blob.services.fetch(media.service_name)
    expect(service.exist?(media.storage_key)).to be(true)
    # A newly checked reservation retains the recovery grace period; advance the
    # test clock, not production policy, before the periodic sweep is due.
    travel_to(6.minutes.from_now) { JrcMigrations::MediaRecoveryJob.perform_now }
    expect(media.reload.status).to eq('cleaned')
    expect(service.exist?(media.storage_key)).to be(false)
  ensure
    reader&.close unless reader&.closed?
    writer&.close unless writer&.closed?
    if worker_pid
      begin
        Process.kill('KILL', worker_pid)
        Process.wait(worker_pid)
      rescue Errno::ESRCH, Errno::ECHILD
        # The synthetic child was already reaped above.
      end
    end
  end

  it 'exposes the durable recovery claim while keeping storage I/O outside the account lock and refusing an upload into that key' do
    preview_media
    media = media_object
    service = ActiveStorage::Blob.services.fetch(media.service_name)
    service.upload(media.storage_key, StringIO.new(bytes))
    deleting = Queue.new
    attempted = Queue.new
    allow(service).to receive(:delete).and_wrap_original do |original, key|
      deleting << true
      Timeout.timeout(10) { attempted.pop }
      original.call(key)
    end
    batch_id = batch.id
    media_id = media.id
    user_id = admin.id
    outcomes = concurrently([
      lambda do
        JrcMigrations::MediaRecovery.new(media: JrcMigrations::MediaObject.find(media_id), user: User.find(user_id)).call
        :recovered
      end,
      lambda do
        Timeout.timeout(10) { deleting.pop }
        expect(JrcMigrations::MediaObject.find(media_id).status).to eq('recovering')
        JrcMigrations::Execute.new(batch: JrcMigrations::Batch.find(batch_id), user: User.find(user_id)).call
        attempted << true
        :upload_refused
      end
    ])
    expect(outcomes).to contain_exactly(:recovered, :upload_refused)
    expect(batch.items.reload.sole).to have_attributes(status: 'failed', error_code: 'MEDIA_PREVIEW_REQUIRED')
    expect(media.reload.status).to eq('cleaned')
    expect(ActiveStorage::Blob.where(key: media.storage_key, service_name: media.service_name)).to be_empty
  ensure
    allow(service).to receive(:delete).and_call_original if service
  end
end
