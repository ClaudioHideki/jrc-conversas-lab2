# rubocop:disable RSpec/SpecFilePathSuffix
# Explicit physical S3 gate: run this file against the disposable MinIO fixture.
# A cross-service opt-in checker, deliberately outside automatic *_spec discovery.
# rubocop:disable RSpec/DescribeClass
require 'rails_helper'
require 'active_storage/service/s3_service'
require 'uri'

RSpec.describe 'Imported media with physical MinIO custody' do
  include_context 'JRC migration media fixtures'

  let(:endpoint) { URI(ENV.fetch('JRC_IMPORT_MINIO_ENDPOINT')) }
  let(:bucket) { "lab2-import-#{SecureRandom.hex(12)}" }
  let(:storage) do
    ActiveStorage::Service::S3Service.new(bucket: bucket, region: 'us-east-1', endpoint: endpoint.to_s,
                                          access_key_id: 'disposable-import', secret_access_key: 'disposable-import-only',
                                          force_path_style: true).tap { |service| service.name = 'jrc_import_minio' }
  end

  before do
    raise 'Disposable loopback or owned Docker MinIO required' unless Rails.env.test? &&
                                                                      %w[127.0.0.1 localhost
                                                                         lab2-import-minio].include?(endpoint.host) && endpoint.scheme == 'http'

    WebMock.disable_net_connect!(allow_localhost: true, allow: "#{endpoint.host}:#{endpoint.port}")
    storage.client.client.create_bucket(bucket: bucket)
    allow(ActiveStorage::Blob).to receive(:service).and_return(storage)
    allow(ActiveStorage::Blob.services).to receive(:fetch).and_call_original
    allow(ActiveStorage::Blob.services).to receive(:fetch).with('jrc_import_minio').and_return(storage)
  end

  after do
    # Only this example's unpredictable bucket, never a shared or productive bucket.
    storage.bucket.objects.each(&:delete)
    storage.client.client.delete_bucket(bucket: bucket)
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  it 'uploads and reads the exact bytes and retains the committed attachment during recovery' do
    blob = execute_media
    expect(blob.download).to eq(bytes)
    expect(JrcMigrations::AttachmentStorage.sha256(blob)).to eq(media_row['file_sha256'])
    expect(media_object).to have_attributes(status: 'attached', blob_id: blob.id)
    JrcMigrations::MediaRecovery.new(media: media_object, user: admin).call
    expect(storage.exist?(blob.key)).to be(true)
    expect(blob.reload.download).to eq(bytes)
  end

  it 'detects physical corruption instead of treating a database record as custody proof' do
    blob = execute_media
    storage.upload(blob.key, StringIO.new('corrupted fixture bytes'))
    expect { JrcMigrations::AttachmentStorage.sha256(blob) }
      .to raise_error(JrcMigrations::Error, 'ATTACHMENT_STORAGE_UNVERIFIED')
  end

  it 'keeps a registered physical object which is not owned by this import attachment' do
    preview_media
    media = media_object
    blob = ActiveStorage::Blob.create_and_upload!(key: media.storage_key, service_name: storage.name,
                                                  io: StringIO.new(bytes), filename: 'keep.pdf', content_type: 'application/pdf')
    JrcMigrations::MediaRecovery.new(media: media, user: admin).call
    expect(media.reload.status).to eq('kept')
    expect(blob.download).to eq(bytes)
  end

  it 'persists a failed cleanup and retries only its orphan key before permitting a new generation' do
    preview_media
    media = media_object
    storage.upload(media.storage_key, StringIO.new(bytes))
    allow(storage).to receive(:delete).with(media.storage_key).and_raise(IOError, 'Injected transport interruption')
    JrcMigrations::MediaRecovery.new(media: media, user: admin).call
    expect(media.reload).to have_attributes(status: 'cleanup_required', error_code: 'ATTACHMENT_CLEANUP_REQUIRED')
    expect(storage.exist?(media.storage_key)).to be(true)
    allow(storage).to receive(:delete).with(media.storage_key).and_call_original
    JrcMigrations::MediaRecovery.new(media: media, user: admin).call
    expect(media.reload.status).to eq('cleaned')
    expect(storage.exist?(media.storage_key)).to be(false)
    blob = execute_media
    expect(blob.key).not_to eq(media.storage_key)
    expect(blob.download).to eq(bytes)
  end
end
# rubocop:enable RSpec/DescribeClass
# rubocop:enable RSpec/SpecFilePathSuffix
