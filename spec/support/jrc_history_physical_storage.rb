# Opt-in, isolated physical storage acceptance. Never uses production credentials
# or permits general outbound networking from the request spec process.
if ENV['HISTORY_PHYSICAL_STORAGE_TEST'] == 'true'
  require 'aws-sdk-s3'
  endpoint = URI.parse(ENV.fetch('STORAGE_ENDPOINT'))
  permitted = endpoint.scheme == 'http' && endpoint.host == 'jrc-history-v2-complete-20261112-minio' && endpoint.port == 9000
  raise 'Only the named disposable local history storage is allowed' unless permitted

  RSpec.configure do |config|
    config.before(:suite) do
      WebMock.disable_net_connect!(allow: 'jrc-history-v2-complete-20261112-minio:9000')
      client = Aws::S3::Client.new(endpoint: endpoint.to_s, region: ENV.fetch('STORAGE_REGION'), force_path_style: true,
                                   access_key_id: ENV.fetch('STORAGE_ACCESS_KEY_ID'), secret_access_key: ENV.fetch('STORAGE_SECRET_ACCESS_KEY'))
      begin
        client.create_bucket(bucket: ENV.fetch('STORAGE_BUCKET_NAME'))
      rescue Aws::S3::Errors::BucketAlreadyOwnedByYou
        # The same private test bucket is deliberately retained across retries.
      end
    end
  end
end
