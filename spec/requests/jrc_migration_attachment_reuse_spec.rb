require 'rails_helper'
require 'base64'

RSpec.describe 'Imported attachment signed IDs do not grant message authority', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:project) { JrcProjects::Project.create!(account: account, owner: admin, key: 'REUSE_IMPORT', name: 'Private import', visibility: 'private') }
  let(:bytes) { "%PDF-1.4\nSynthetic imported attachment reuse\n%%EOF\n".b }
  let(:widget) { create(:channel_widget, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:identity) { create(:contact_inbox, contact: contact, inbox: widget.inbox) }
  let(:conversation) { create(:conversation, account: account, contact: contact, inbox: widget.inbox, contact_inbox: identity) }

  before do
    account.enable_features!('jrc_projects', 'data_import')
    create(:inbox_member, inbox: widget.inbox, user: admin)
  end
  after { clear_enqueued_jobs }

  def imported_blob(domain = 'project_attachments')
    parent = domain == 'project_attachments' ? project : JrcProjects::Task.create!(account: account, project: project, created_by: admin, title: 'File task')
    parent_key = domain == 'project_attachments' ? 'project_id' : 'task_id'
    row = { 'legacy_id' => 'reuse-file', parent_key => parent.id, 'filename' => 'history.pdf', 'content_type' => 'application/pdf',
            'file_base64' => Base64.strict_encode64(bytes), 'file_sha256' => Digest::SHA256.hexdigest(bytes), 'file_size' => bytes.bytesize,
            'created_at' => '2021-01-02T12:00:00Z', 'updated_at' => '2021-01-02T12:00:00Z' }
    batch = JrcMigrations::Stage.new(account: account, user: admin).call(source: 'signed-id-reuse-fixture', domain: domain, rows: [row], mapping: {})
    JrcMigrations::Preview.new(batch: batch, user: admin).call
    JrcMigrations::Execute.new(batch: batch, user: admin).call
    expect(batch.items.reload.sole.status).to eq('applied')
    parent.attachments_attachments.sole.blob
  end

  def scanned!(blob)
    blob.update!(metadata: blob.metadata.merge('service_desk_scan_state' => 'clean', 'service_desk_scan_adapter' => 'clamav-instream-v1',
      'service_desk_scan_sha256' => Digest::SHA256.hexdigest(bytes), 'service_desk_scanned_at' => Time.current.iso8601(6)))
  end

  def post_outgoing(blob, user: admin, target: conversation)
    post "/api/v1/accounts/#{target.account_id}/conversations/#{target.display_id}/messages", headers: user.create_new_auth_token,
      as: :json, params: { content: 'Synthetic reuse', message_type: 'outgoing', private: false, attachments: [blob.signed_id] }
  end

  def reader_with_project_access
    user = create(:user, account: account, role: :agent)
    account.account_users.find_by!(user: user).update!(jrc_projects_enabled: true)
    create(:inbox_member, inbox: widget.inbox, user: user)
    member = JrcProjects::ProjectMember.create!(account: account, project: project, user: user, role: 'viewer')
    [user, member]
  end

  def queued_message(blob, user: admin)
    message = create(:message, account: account, inbox: widget.inbox, conversation: conversation, sender: user,
                               message_type: :outgoing, private: false, content: 'Synthetic queued reuse')
    message.attachments.create!(account: account, file_type: :file, file: blob)
    clear_enqueued_jobs
    message
  end

  def observe_provider_boundary(message)
    provider = instance_double(Messages::SendEmailNotificationService, perform: true)
    allow(Messages::SendEmailNotificationService).to receive(:new).and_return(provider)
    SendReplyJob.perform_now(message.id)
  end

  it 'denies message creation from an unscanned import even to the authorized project owner' do
    blob = imported_blob
    target = conversation
    expect { post_outgoing(blob, target: target) }.not_to change(Message, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'denies clean imported bytes to a foreign Account while preserving its own conversation authority' do
    blob = imported_blob
    scanned!(blob)
    foreign = create(:account)
    foreign_user = create(:user, account: foreign, role: :administrator)
    foreign_inbox = create(:inbox, account: foreign)
    create(:inbox_member, inbox: foreign_inbox, user: foreign_user)
    target = create(:conversation, account: foreign, inbox: foreign_inbox)
    expect { post_outgoing(blob, user: foreign_user, target: target) }.not_to change(Message, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'denies a clean signed ID after project access is revoked without revoking inbox access' do
    blob = imported_blob
    scanned!(blob)
    reader, membership = reader_with_project_access
    target = conversation
    expect(JrcMigrations::ProtectedBlobAccess.new(blob: blob, user: reader).allowed?).to be(true)
    membership.destroy!
    expect { post_outgoing(blob, user: reader, target: target) }.not_to change(Message, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'keeps tenant isolation when the same operator administers both source and destination accounts' do
    blob = imported_blob
    scanned!(blob)
    foreign = create(:account)
    create(:account_user, account: foreign, user: admin, role: :administrator)
    foreign_inbox = create(:inbox, account: foreign)
    create(:inbox_member, inbox: foreign_inbox, user: admin)
    target = create(:conversation, account: foreign, inbox: foreign_inbox)
    expect { post_outgoing(blob, user: admin, target: target) }.not_to change(Message, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'stops a queued unscanned import before invoking the channel service' do
    message = queued_message(imported_blob)
    observe_provider_boundary(message)
    expect(Messages::SendEmailNotificationService).not_to have_received(:new)
    expect(message.reload).to be_failed
  end

  it 'rechecks revoked project access at the queued-message provider boundary' do
    blob = imported_blob
    scanned!(blob)
    reader, membership = reader_with_project_access
    message = queued_message(blob, user: reader)
    expect(JrcMigrations::ProtectedBlobAccess.new(blob: blob, user: reader).allowed?).to be(true)
    membership.destroy!
    observe_provider_boundary(message)
    expect(Messages::SendEmailNotificationService).not_to have_received(:new)
    expect(message.reload).to be_failed
  end

  %w[project_attachments project_task_attachments].each do |domain|
    it "does not let a Widget token reattach clean #{domain} bytes by signed ID" do
      blob = imported_blob(domain)
      scanned!(blob)
      target = conversation
      headers = { 'X-Auth-Token' => Widget::TokenService.new(payload: { source_id: identity.source_id, inbox_id: widget.inbox.id }).generate_token }
      expect do
        post '/api/v1/widget/messages', headers: headers,
          params: { website_token: widget.website_token, message: { content: 'Synthetic widget reuse', attachments: [blob.signed_id] } }
      end.not_to change(target.messages, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it 'preserves ordinary native signed-ID creation and the existing provider boundary' do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(bytes), filename: 'native.pdf', content_type: 'application/pdf')
    target = conversation
    expect { post_outgoing(blob, target: target) }.to change(Message, :count).by(1)
    expect(response).to have_http_status(:ok)
    message = Message.find(response.parsed_body.fetch('id'))
    expect(message.attachments.sole.file.blob_id).to eq(blob.id)
    observe_provider_boundary(message)
    expect(Messages::SendEmailNotificationService).to have_received(:new).with(message: message)
  end
end
