require 'rails_helper'
require 'active_storage/service/s3_service'

RSpec.describe 'Migration storage identity across configuration changes' do
  it 'permits credential rotation while distinguishing bucket and endpoint changes without issuing requests' do
    options = { bucket: 'synthetic-import-bucket', region: 'us-east-1', endpoint: 'http://synthetic-storage.invalid',
                access_key_id: 'synthetic-key-a', secret_access_key: 'synthetic-secret-a', force_path_style: true }
    original = ActiveStorage::Service::S3Service.new(**options)
    rotated = ActiveStorage::Service::S3Service.new(**options.merge(access_key_id: 'synthetic-key-b', secret_access_key: 'synthetic-secret-b'))
    different_bucket = ActiveStorage::Service::S3Service.new(**options.merge(bucket: 'synthetic-other-bucket'))
    different_endpoint = ActiveStorage::Service::S3Service.new(**options.merge(endpoint: 'http://synthetic-other-storage.invalid'))
    identity = JrcMigrations::StorageIdentity.fingerprint(original)
    expect(JrcMigrations::StorageIdentity.fingerprint(rotated)).to eq(identity)
    expect(JrcMigrations::StorageIdentity.fingerprint(different_bucket)).not_to eq(identity)
    expect(JrcMigrations::StorageIdentity.fingerprint(different_endpoint)).not_to eq(identity)
    expect(identity).to match(/\A[a-f0-9]{64}\z/)
  end
end
