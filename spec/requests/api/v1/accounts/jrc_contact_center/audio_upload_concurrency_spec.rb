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

  include_context 'institutional audio receipt'

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

  def race_staged_receipts(&operation)
    identifiers = { account: account.id, user: actor.id, account_user: member.id }
    allow(JrcContactCenter::PrivateAudioBlob).to receive(:upload).and_wrap_original do |original, **values|
      stored = original.call(**values)
      arrived << true
      Timeout.timeout(15) { release.pop }
      stored
    end
    2.times do |index|
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          fresh = { account: Account.find(identifiers[:account]), user: User.find(identifiers[:user]),
                    account_user: AccountUser.find(identifiers[:account_user]) }
          Tempfile.create(['synthetic-concurrent-audio', '.wav']) do |file|
            file.binmode
            file.write(bytes)
            file.rewind
            uploaded = ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: 'SYNTHETIC.wav', type: 'audio/wav')
            service = JrcContactCenter::AudioUploads.new(access: JrcContactCenter::AudioLibraryAccess.new(context: fresh))
            results << operation.call(service, uploaded, index)
          end
        end
      rescue StandardError => error
        results << error
      end
    end
    2.times { Timeout.timeout(20) { arrived.pop } }
    2.times { release << true }
    2.times.map { Timeout.timeout(25) { results.pop } }
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
  end

  it 'keeps the native orphan-purge path harmless for committed private history without weakening its foreign-key protection' do
    original = JrcContactCenter::AudioUploads.new(access: JrcContactCenter::AudioLibraryAccess.new(context: context))
                                           .create!(unit_id: unit.id, attributes: { name: 'SYNTHETIC protected purge' }, file: upload, key: key)
    expect { original.blob.purge }.not_to raise_error
    expect(ActiveStorage::Blob.exists?(original.blob_id)).to be(true)
    expect(original.reload.blob.download).to eq(bytes)
  end
end
