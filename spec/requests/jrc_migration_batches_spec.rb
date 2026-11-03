require 'rails_helper'

RSpec.describe 'Migration Center', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/jrc_migration_batches" }
  let(:payload) do
    { source: 'fixture', domain: 'contacts', mapping: {},
      rows: [{ legacy_id: '1', name: 'Fixture', created_at: '2020-01-01T00:00:00Z', updated_at: '2020-01-01T00:00:00Z' }] }
  end

  before { account.enable_features!('data_import') }

  it 'rejects non-administrators and accounts without the feature' do
    get url, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
    account.disable_features!('data_import')
    post url, headers: admin.create_new_auth_token, params: payload, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'stages, previews and executes only through explicit scoped actions' do
    expect { post url, headers: admin.create_new_auth_token, params: payload, as: :json }.not_to change(Contact, :count)
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch('id')
    post "#{url}/#{id}/preview", headers: admin.create_new_auth_token
    expect(response.parsed_body.fetch('items').first['decision']).to eq('create')
    expect { post "#{url}/#{id}/execute", headers: admin.create_new_auth_token }.to change(Contact, :count).by(1)
    expect(response.parsed_body['status']).to eq('executed')
    get "#{url}/#{id}/reconciliation", headers: admin.create_new_auth_token
    expect(response.parsed_body['matched']).to eq(1)
  end

  it 'does not reveal foreign batches or accept after role revocation' do
    batch = JrcMigrations::Stage.new(account: account, user: admin).call(**payload)
    foreign = create(:account)
    foreign.enable_features!('data_import')
    foreign_admin = create(:user, account: foreign, role: :administrator)
    get "/api/v1/accounts/#{foreign.id}/jrc_migration_batches/#{batch.id}", headers: foreign_admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    account.account_users.find_by!(user_id: admin.id).update!(role: :agent)
    post "#{url}/#{batch.id}/accept", headers: admin.create_new_auth_token, params: { note: 'No longer authorized' }
    expect(response).to have_http_status(:forbidden)
  end

  it 'keeps file bytes and private cleanup state out of batch responses while retaining reviewable metadata' do
    project = JrcProjects::Project.create!(account: account, owner: admin, key: 'FILES', name: 'Files')
    bytes = '%PDF-1.4 synthetic'.b
    row = { legacy_id: 'file-1', project_id: project.id, filename: 'source.pdf', content_type: 'application/pdf',
            file_base64: Base64.strict_encode64(bytes), file_sha256: Digest::SHA256.hexdigest(bytes), file_size: bytes.bytesize,
            created_at: '2020-01-01T00:00:00Z', updated_at: '2020-01-01T00:00:00Z' }
    post url, headers: admin.create_new_auth_token, params: { source: 'fixture', domain: 'project_attachments', rows: [row], mapping: {} }, as: :json
    expect(response).to have_http_status(:created)
    item = response.parsed_body.fetch('items').sole
    expect(item.fetch('normalized_data')).to include('filename' => 'source.pdf', 'file_sha256' => row[:file_sha256])
    expect(item.fetch('normalized_data')).not_to have_key('file_base64')
    expect(item.keys).not_to include('raw_data', 'before_data')
  end
end
