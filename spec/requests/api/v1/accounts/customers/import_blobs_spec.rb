require 'rails_helper'

RSpec.describe 'Private customer import blobs', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, role: :administrator) }
  let(:runs) { JrcCustomers::ImportRuns.new(account: account, actor: actor) }
  let(:run) { runs.create!(content: "name\nPrivate company\n", kind: 'companies', filename: 'private.csv') }
  let(:blob) { run.import_file.blob }

  before { account.enable_features!('jrc_customer_master') }

  it 'denies both generic blob transports even to an authenticated administrator' do
    get rails_blob_path(blob, only_path: true), headers: actor.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    expect(response.headers['Cache-Control']).to include('no-store')
    get rails_storage_proxy_path(blob, only_path: true), headers: actor.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('Private company')
  end

  it 'denies the storage disk locator without relying on an authenticated session' do
    data = { key: blob.key, disposition: 'attachment', content_type: 'text/csv', service_name: blob.service_name }
    token = ActiveStorage.verifier.generate(data, purpose: :blob_key, expires_in: 5.minutes)
    get rails_disk_service_path(token, 'private.csv')
    expect(response).to have_http_status(:not_found)
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'preserves ordinary native attachment delivery' do
    public_blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('native attachment'), filename: 'native.txt', content_type: 'text/plain')
    get rails_blob_path(public_blob, only_path: true)
    expect(response).to have_http_status(:redirect)
  end
end
