require 'rails_helper'
require 'timeout'

RSpec.describe 'Institutional private audio serializes uncertain native receipts', type: :request do
  self.use_transactional_tests = false

  before do
    config = ActiveRecord::Base.connection_db_config
    owned = Rails.env.test? && ENV['GITHUB_ACTIONS'] == 'true' && ENV['RUNNER_ENVIRONMENT'] == 'github-hosted' &&
            config.configuration_hash[:host] == '127.0.0.1' && config.database == 'corporate_gratuity_disposable'
    raise 'Exclusive synthetic committed audio database required' unless owned && !ActiveRecord::Base.connection.transaction_open?
  end

  include_context 'with an institutional audio receipt'

  let(:workers) { [] }
  let(:arrived) { Queue.new }
  let(:release) { Queue.new }
  let(:results) { Queue.new }

  after do
    2.times { release << true }
    workers.each { |worker| worker.join(20) }
    raise 'Owned synthetic audio worker still active' if workers.any?(&:alive?)

    # Append-only synthetic versions and their bytes remain in this job's disposable DB/storage
    # until runner teardown. Do not disable triggers or delete accepted history as test cleanup.
  end

  def race_staged_receipts(service_class: JrcContactCenter::AudioUploads)
    identifiers = { account: account.id, user: actor.id, account_user: member.id }
    stage_barrier
    2.times do |index|
      workers << Thread.new { execute_worker(identifiers, index, service_class) { |*arguments| yield(*arguments) } }
    end
    2.times { Timeout.timeout(20) { arrived.pop } }
    2.times { release << true }
    Array.new(2) { Timeout.timeout(25) { results.pop } }
  end

  def stage_barrier
    allow(JrcContactCenter::PrivateAudioBlob).to receive(:upload).and_wrap_original do |original, **values|
      stored = original.call(**values)
      arrived << true
      Timeout.timeout(15) { release.pop }
      stored
    end
  end

  def execute_worker(identifiers, index, service_class)
    ActiveRecord::Base.connection_pool.with_connection do
      service = service_class.new(access: JrcContactCenter::AudioLibraryAccess.new(context: worker_context(identifiers)))
      concurrent_upload do |uploaded|
        results << yield(service, uploaded, index)
      end
    end
  rescue StandardError => e
    results << e
  end

  def worker_context(identifiers)
    { account: Account.find(identifiers[:account]), user: User.find(identifiers[:user]), account_user: AccountUser.find(identifiers[:account_user]) }
  end

  def concurrent_upload
    Tempfile.create(['synthetic-concurrent-audio', '.wav']) do |file|
      file.binmode
      file.write(bytes)
      file.rewind
      yield ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: 'SYNTHETIC.wav', type: 'audio/wav')
    end
  end

  it 'commits exactly one version and compensates the redundant owned staging blob for simultaneous identical request keys' do
    unit_id = unit.id
    key_value = key
    original_blobs = ActiveStorage::Blob.count
    outcomes = race_staged_receipts do |service, uploaded, _index|
      service.create!(unit_id: unit_id, attributes: { name: 'SYNTHETIC simultaneous' }, file: uploaded, key: key_value)
    end
    expect(outcomes.map(&:class)).to eq([JrcContactCenter::AudioVersion, JrcContactCenter::AudioVersion])
    expect(outcomes.map(&:id).uniq.length).to eq(1)
    expect(JrcContactCenter::AudioAsset.where(account: account).count).to eq(1)
    expect(JrcContactCenter::AudioVersion.where(account: account).count).to eq(1)
    expect(ActiveStorage::Blob.count).to eq(original_blobs + 1)
    expect(JrcContactCenter::AudioInspection.where(account: account).count).to eq(1)
    expect(JrcContactCenter::AudioInspection.where(account: account).sole.ready?).to be(true)
  end

  it 'allows only one actual replacement when two different uploads reviewed the same exact prior version' do
    first = JrcContactCenter::AudioUploads.new(access: JrcContactCenter::AudioLibraryAccess.new(context: context))
                                          .create!(unit_id: unit.id, attributes: { name: 'SYNTHETIC existing' }, file: upload, key: key)
    expected = JrcContactCenter::AudioAssetRevision.token(first.audio_asset, version: first)
    original_blobs = ActiveStorage::Blob.count
    outcomes = race_staged_receipts do |service, uploaded, index|
      service.replace!(asset_id: first.audio_asset_id, file: uploaded, key: "synthetic-concurrent-replace-#{index}", expected: expected)
    end
    expect(outcomes.count { |row| row.is_a?(JrcContactCenter::AudioVersion) }).to eq(1)
    expect(outcomes.select { |row| row.is_a?(JrcContactCenter::OperationError) }.map(&:code)).to eq(['stale_configuration_revision'])
    expect(JrcContactCenter::AudioVersion.where(audio_asset_id: first.audio_asset_id).order(:number).pluck(:number)).to eq([1, 2])
    expect(ActiveStorage::Blob.count).to eq(original_blobs + 1)
    expect(first.reload.blob.download).to eq(bytes)
    expect(JrcContactCenter::AudioInspection.where(account: account).order(:audio_version_id).pluck(:attempt)).to eq([1, 1])
  end

  it 'keeps the native orphan-purge path harmless for committed private history without weakening its foreign-key protection' do
    original = JrcContactCenter::AudioUploads.new(access: JrcContactCenter::AudioLibraryAccess.new(context: context))
                                             .create!(unit_id: unit.id, attributes: { name: 'SYNTHETIC protected purge' }, file: upload, key: key)
    expect { original.blob.purge }.not_to raise_error
    expect(ActiveStorage::Blob.exists?(original.blob_id)).to be(true)
    expect(original.reload.blob.download).to eq(bytes)
  end

  it 'commits one independent copy and cleans only redundant staging for simultaneous identical copy requests' do
    first = JrcContactCenter::AudioUploads.new(access: JrcContactCenter::AudioLibraryAccess.new(context: context))
                                          .create!(unit_id: unit.id, file: upload, key: key,
                                                   attributes: { name: 'SYNTHETIC source for concurrent copy' })
    request = { asset_id: first.audio_asset_id, version_id: first.id, attributes: { name: 'SYNTHETIC concurrent copy' },
                key: 'synthetic-concurrent-copy-0001', expected: JrcContactCenter::AudioAssetRevision.token(first.audio_asset, version: first) }
    original_blobs = ActiveStorage::Blob.count
    outcomes = race_staged_receipts(service_class: JrcContactCenter::AudioCopies) { |service, _file, _index| service.call(**request) }
    expect(outcomes.map(&:class)).to eq([JrcContactCenter::AudioVersion, JrcContactCenter::AudioVersion])
    expect(outcomes.map(&:id).uniq.length).to eq(1)
    expect(JrcContactCenter::AudioAsset.where(account: account).count).to eq(2)
    expect(ActiveStorage::Blob.count).to eq(original_blobs + 1)
    expect(Audited.audit_class.where(auditable: outcomes.first, action: 'copy').count).to eq(1)
    expect(outcomes.first.audio_asset_id).not_to eq(first.audio_asset_id)
    expect([first.reload.blob.download, outcomes.first.blob.download]).to eq([bytes, bytes])
  end

  it 'refuses a raced copy key bound to different metadata without creating a second copy or changing the original' do
    first = JrcContactCenter::AudioUploads.new(access: JrcContactCenter::AudioLibraryAccess.new(context: context))
                                          .create!(unit_id: unit.id, file: upload, key: key,
                                                   attributes: { name: 'SYNTHETIC source for conflicting copy' })
    request = { asset_id: first.audio_asset_id, version_id: first.id, key: 'synthetic-conflicting-copy-0001',
                expected: JrcContactCenter::AudioAssetRevision.token(first.audio_asset, version: first) }
    original_blobs = ActiveStorage::Blob.count
    outcomes = race_staged_receipts(service_class: JrcContactCenter::AudioCopies) do |service, _file, index|
      service.call(**request, attributes: { name: "SYNTHETIC competing copy #{index}" })
    end
    expect(outcomes.count { |row| row.is_a?(JrcContactCenter::AudioVersion) }).to eq(1)
    expect(outcomes.select { |row| row.is_a?(JrcContactCenter::OperationError) }.map(&:code)).to eq(['institutional_audio_upload_key_conflict'])
    expect(JrcContactCenter::AudioAsset.where(account: account).count).to eq(2)
    expect(JrcContactCenter::AudioVersion.where(account: account).count).to eq(2)
    expect(ActiveStorage::Blob.count).to eq(original_blobs + 1)
    expect(first.reload.audio_asset.name).to eq('SYNTHETIC source for conflicting copy')
  end
  def dispatch_audio_metadata_move(endpoint, headers, payload, barrier: false)
    workers << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        arrived << ActiveRecord::Base.connection.raw_connection.backend_pid
        Timeout.timeout(10) { release.pop } if barrier
        session = ActionDispatch::Integration::Session.new(Rails.application)
        session.post(endpoint, headers: headers, params: payload, as: :json)
        results << session.response.status
      end
    rescue StandardError => e
      results << e
    end
  end

  it 'accepts one concurrent reviewed metadata move and denies stale replay without partially updating the selection' do
    sources = Array.new(2) do |index|
      JrcContactCenter::AudioAsset.create!(account: account, unit: unit, name: "SYNTHETIC simultaneous metadata #{index}")
    end
    destination = JrcContactCenter::AudioFolder.create!(account: account, unit: unit, name: 'SYNTHETIC simultaneous destination')
    payload = { unit_id: unit.id.to_s, folder_id: destination.id.to_s, items: sources.map do |record|
      { audio_asset_id: record.id.to_s, expected_revision: JrcContactCenter::AudioAssetRevision.token(record, version: nil) }
    end }
    endpoint = "/api/v1/accounts/#{account.id}/jrc_contact_center/audio_asset_moves"
    headers = actor.create_new_auth_token
    before_audits = Audited.audit_class.where(auditable: sources, action: 'update').count
    2.times { dispatch_audio_metadata_move(endpoint, headers, payload, barrier: true) }
    Timeout.timeout(10) { 2.times { arrived.pop } }
    2.times { release << true }
    Timeout.timeout(25) { workers.each(&:join) }
    outcomes = Array.new(2) { results.pop }
    expect(outcomes).to all(be_a(Integer))
    expect(outcomes.sort).to eq([200, 409])
    expect(sources.map { |record| record.reload.folder_id }).to eq([destination.id, destination.id])
    expect(Audited.audit_class.where(auditable: sources, action: 'update').count - before_audits).to eq(2)
    expect(JrcContactCenter::AudioVersion.where(account: account)).to be_empty
  end

  it 'reauthorizes a queued real metadata request after an actual Account lock and committed profile withdrawal' do
    record = JrcContactCenter::AudioAsset.create!(account: account, unit: unit, name: 'SYNTHETIC locked metadata source')
    destination = JrcContactCenter::AudioFolder.create!(account: account, unit: unit, name: 'SYNTHETIC locked destination')
    payload = { unit_id: unit.id.to_s, folder_id: destination.id.to_s,
                items: [{ audio_asset_id: record.id.to_s, expected_revision: JrcContactCenter::AudioAssetRevision.token(record, version: nil) }] }
    headers = actor.create_new_auth_token
    role_id = member.custom_role_id
    account_id = account.id
    workers << Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Account.find(account_id).with_lock do
          arrived << true
          Timeout.timeout(15) { release.pop }
          CustomRole.find(role_id).update!(permissions: ['jrc_contact_center_view'])
        end
      end
    rescue StandardError => e
      results << e
    end
    Timeout.timeout(10) { arrived.pop }
    dispatch_audio_metadata_move("/api/v1/accounts/#{account.id}/jrc_contact_center/audio_asset_moves", headers, payload)
    pid = Timeout.timeout(10) { arrived.pop }
    Timeout.timeout(8) do
      loop do
        sql = "SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE pid = #{Integer(pid)} AND wait_event_type = 'Lock' " \
              "AND query LIKE '%accounts%' AND query LIKE '%FOR UPDATE%')"
        break if ActiveRecord::Base.connection.uncached { ActiveRecord::Base.connection.select_value(sql) }

        sleep 0.02
      end
    end
    release << true
    Timeout.timeout(25) { workers.each(&:join) }
    expect(results.size).to eq(1)
    expect(results.pop).to eq(401)
    expect(record.reload.folder_id).to be_nil
    expect(Audited.audit_class.where(auditable: record, action: 'update')).to be_empty
    expect(member.custom_role.reload.permissions).to eq(['jrc_contact_center_view'])
  end

end
