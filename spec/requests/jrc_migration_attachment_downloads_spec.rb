require 'rails_helper'
require 'base64'

RSpec.describe 'Imported project files retain current download authority', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:project) { JrcProjects::Project.create!(account: account, owner: admin, key: 'DL_IMPORT', name: 'Imported files', visibility: 'private') }
  let(:bytes) { "%PDF-1.4\nSynthetic protected history\n%%EOF\n".b }

  before { account.enable_features!('jrc_projects') }

  def import_file(domain)
    parent = attachment_parent(domain)
    parent_key = domain == 'project_attachments' ? 'project_id' : 'task_id'
    row = { 'legacy_id' => 'download-file', parent_key => parent.id, 'filename' => 'history.pdf', 'content_type' => 'application/pdf',
            'file_base64' => Base64.strict_encode64(bytes), 'file_sha256' => Digest::SHA256.hexdigest(bytes), 'file_size' => bytes.bytesize,
            'created_at' => '2021-01-02T12:00:00Z', 'updated_at' => '2021-01-02T12:00:00Z' }
    execute_import(row, domain)
    parent.attachments_attachments.sole.blob
  end

  def execute_import(row, domain)
    batch = JrcMigrations::Stage.new(account: account, user: admin).call(source: 'download_fixture', domain: domain, rows: [row], mapping: {})
    JrcMigrations::Preview.new(batch: batch, user: admin).call
    JrcMigrations::Execute.new(batch: batch, user: admin).call
    expect(batch.items.reload.sole.status).to eq('applied')
  end

  def attachment_parent(domain)
    return project if domain == 'project_attachments'

    JrcProjects::Task.create!(account: account, project: project, created_by: admin, title: 'Imported file task')
  end

  def scanned!(blob)
    # Synthetic scanner evidence only; the test still checks actual stored bytes.
    blob.update!(metadata: blob.metadata.merge('service_desk_scan_state' => 'clean', 'service_desk_scan_adapter' => 'clamav-instream-v1',
                                               'service_desk_scan_sha256' => Digest::SHA256.hexdigest(bytes),
                                               'service_desk_scanned_at' => Time.current.iso8601(6)))
  end

  %w[project_attachments project_task_attachments].each do |domain|
    context domain do
      let(:blob) { import_file(domain) }
      let(:download_path) { Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true) }

      it 'denies unavailable scans even to the authorized owner' do
        get download_path, headers: admin.create_new_auth_token
        expect(response).to have_http_status(:not_found)
        expect(response.headers['Location']).to be_nil
        expect(response.body).not_to include(bytes)
      end

      it 'denies an anonymous or foreign-account replay of the owner signed URL' do
        scanned!(blob)
        foreign_admin = create(:user, account: create(:account), role: :administrator)
        proxy = Rails.application.routes.url_helpers.rails_storage_proxy_path(blob, only_path: true)
        disk = ActiveStorage::Current.set(url_options: { host: 'www.example.com' }) { URI.parse(blob.url).request_uri }
        [download_path, proxy, disk].each do |path|
          get path
          expect(response).to have_http_status(:not_found)
          get path, headers: foreign_admin.create_new_auth_token
          expect(response).to have_http_status(:not_found)
          expect(response.headers['Location']).to be_nil
        end
      end

      it 'streams verified bytes without a storage redirect and rechecks revoked project membership' do
        reader = create(:user, account: account, role: :agent)
        account.account_users.find_by!(user: reader).update!(jrc_projects_enabled: true)
        membership = JrcProjects::ProjectMember.create!(account: account, project: project, user: reader, role: 'viewer')
        scanned!(blob)
        headers = reader.create_new_auth_token
        get download_path, headers: headers
        expect(response).to have_http_status(:ok)
        expect(response.body).to eq(bytes)
        expect(response.headers['Cache-Control']).to include('no-store')
        expect(response.headers['Location']).to be_nil
        membership.destroy!
        get download_path, headers: headers
        expect(response).to have_http_status(:not_found)
      end

      it 'denies changed physical bytes despite a previously clean scan and current project authority' do
        scanned!(blob)
        blob.service.upload(blob.key, StringIO.new('changed physical bytes'))
        get download_path, headers: admin.create_new_auth_token
        expect(response).to have_http_status(:not_found)
        expect(response.headers['Location']).to be_nil
      end

      it 'does not borrow authority from a reattachment or release an orphaned original' do
        scanned!(blob)
        reader = create(:user, account: account, role: :agent)
        account.account_users.find_by!(user: reader).update!(jrc_projects_enabled: true)
        destination = JrcProjects::Project.create!(account: account, owner: reader, key: 'DEST_IMPORT', name: 'Other private project',
                                                   visibility: 'private')
        original = blob.attachments.sole
        destination.attachments.attach(blob)
        get download_path, headers: reader.create_new_auth_token
        expect(response).to have_http_status(:not_found)
        original.delete # Retain bytes and the reattachment; the original provenance link no longer exists.
        get download_path, headers: admin.create_new_auth_token
        expect(response).to have_http_status(:not_found)
      end

      it 'compares a later clean scan against the immutable staged file hash' do
        scanned!(blob)
        changed = "%PDF-1.4\nA different scanned file\n%%EOF\n".b
        blob.service.upload(blob.key, StringIO.new(changed))
        blob.update!(checksum: Digest::MD5.base64digest(changed), byte_size: changed.bytesize,
                     metadata: blob.metadata.merge('service_desk_scan_sha256' => Digest::SHA256.hexdigest(changed)))
        get download_path, headers: admin.create_new_auth_token
        expect(response).to have_http_status(:not_found)
        expect(response.headers['Location']).to be_nil
      end
    end
  end

  it 'preserves the existing signed download path for an ordinary native project attachment' do
    project.attachments.attach(io: StringIO.new(bytes), filename: 'native.pdf', content_type: 'application/pdf')
    blob = project.attachments_attachments.sole.blob
    get Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
    expect(response).to have_http_status(:found)
  end
end
