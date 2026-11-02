# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk attachment authority across every protected owner', type: :request do
  include_context 'JRC Service Desk domain'

  let(:company) { JrcCustomers::Company.create!(account: sd_account, name: 'Synthetic attachment customer') }
  let(:sd_contact) { create(:contact, account: sd_account, company_id: company.id, identifier: SecureRandom.uuid) }
  let(:widget) { create(:channel_widget, account: sd_account) }
  let(:identity) { create(:contact_inbox, contact: sd_contact, inbox: widget.inbox, hmac_verified: true) }
  let(:conversation) { create(:conversation, account: sd_account, inbox: widget.inbox, contact: sd_contact, contact_inbox: identity) }
  let(:ticket) { sd_ticket }
  let(:portal_user) { create(:user) }
  let(:grant) do
    JrcServiceDesk::PortalGrant.create!(account: sd_account, user: portal_user, company: company, contact: sd_contact,
                                      inbox: widget.inbox, contact_inbox: identity, granted_by: sd_user, active: true)
  end
  let(:native) { ActionDispatch::Integration::Session.new(Rails.application) }
  let(:native_headers) { sd_user.create_new_auth_token }
  let(:messages_path) { "/api/v1/accounts/#{sd_account.id}/conversations/#{conversation.display_id}/messages" }
  let(:timeline_path) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/tickets/#{ticket.id}/timeline/message" }
  let(:scan_proof) do
    { 'service_desk_scan_state' => 'clean', 'service_desk_scan_adapter' => 'clamav-instream-v1',
      'service_desk_scan_sha256' => Digest::SHA256.file(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt')).hexdigest,
      'service_desk_scanned_at' => Time.current.iso8601(6) }
  end

  before do
    sd_as_admin!
    sd_account.enable_features!('jrc_customer_master')
    sd_account.update!(internal_attributes: sd_account.internal_attributes.merge('requester_portal_enabled' => true))
    create(:inbox_member, inbox: widget.inbox, user: sd_user)
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
    grant
    post '/portal/session', params: {}, headers: portal_user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
  end

  it 'denies a real outgoing signed_id reattachment after its native author loses the source ticket note rights' do
    source_ticket = create(:jrc_sd_ticket, unit: sd_other_unit)
    source_note = create(:jrc_sd_note, ticket: source_ticket,
                                       files: [fixture_file_upload(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt'), 'text/plain')])
    blob = source_note.files.first.blob
    blob.update!(metadata: blob.metadata.merge(scan_proof))
    native.post messages_path, headers: native_headers, as: :json, params: {
      content: 'Synthetic outgoing reattachment', message_type: 'outgoing', private: false,
      attachments: [blob.signed_id], content_attributes: { service_desk_ticket_id: ticket.id.to_s }
    }
    expect(native.response).to have_http_status(:ok), native.response.body
    message = Message.find(native.response.parsed_body.fetch('id'))
    attachment = message.attachments.sole
    expect(attachment.file.blob_id).to eq(blob.id)
    sd_account_user.update!(role: :agent)
    expect(JrcServiceDesk::TicketNotePolicy.new(sd_context, source_note).show?).to be(false)

    native.get "#{timeline_path}/#{message.id}/attachments/#{attachment.id}", headers: native_headers
    expect(native.response).to have_http_status(:not_found)
    expect(native.response.body).not_to include('Project attachment test')

    get "/portal/api/chamados/#{ticket.id}/respostas/#{message.id}/anexos/#{attachment.id}"
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('Project attachment test')
  end

  it 'rejects an unauthorized source signed_id before creating the outgoing native message' do
    source_ticket = create(:jrc_sd_ticket, unit: sd_other_unit)
    source_note = create(:jrc_sd_note, ticket: source_ticket,
                                       files: [fixture_file_upload(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt'), 'text/plain')])
    blob = source_note.files.first.blob
    blob.update!(metadata: blob.metadata.merge(scan_proof))
    sd_account_user.update!(role: :agent)

    expect do
      native.post messages_path, headers: native_headers, as: :json, params: {
        content: 'Unauthorized synthetic source', message_type: 'outgoing', private: false, attachments: [blob.signed_id]
      }
    end.not_to change(conversation.messages, :count)
    expect(native.response).to have_http_status(:unprocessable_entity)
  end

  it 'keeps an own public multipart upload available to both its native author and the authorized requester' do
    native.post messages_path, headers: native_headers, params: {
      content: 'Synthetic own public upload', message_type: 'outgoing', private: false,
      attachments: [fixture_file_upload(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt'), 'text/plain')],
      content_attributes: { service_desk_ticket_id: ticket.id.to_s }
    }
    expect(native.response).to have_http_status(:ok), native.response.body
    message = Message.find(native.response.parsed_body.fetch('id'))
    attachment = message.attachments.sole
    attachment.file.blob.update!(metadata: scan_proof)

    native.get "#{timeline_path}/#{message.id}/attachments/#{attachment.id}", headers: native_headers
    expect(native.response).to have_http_status(:ok), native.response.body
    expect(native.response.body).to eq(File.read(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt')))

    get "/portal/api/chamados/#{ticket.id}/respostas/#{message.id}/anexos/#{attachment.id}"
    expect(response).to have_http_status(:ok), response.body
    expect(response.body).to eq(File.read(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt')))
  end

  it 'does not borrow operational rights when a native operator downloads through their requester context' do
    operator_grant = JrcServiceDesk::PortalGrant.create!(account: sd_account, user: sd_user, company: company, contact: sd_contact,
                                                       inbox: widget.inbox, contact_inbox: identity, granted_by: sd_user, active: true)
    source_note = create(:jrc_sd_note, ticket: ticket,
                                       files: [fixture_file_upload(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt'), 'text/plain')])
    blob = source_note.files.first.blob
    blob.update!(metadata: blob.metadata.merge(scan_proof))
    expect(JrcServiceDesk::TicketNotePolicy.new(sd_context, source_note).show?).to be(true)

    native.post messages_path, headers: native_headers, as: :json, params: {
      content: 'Synthetic shared internal evidence', message_type: 'outgoing', private: false,
      attachments: [blob.signed_id], content_attributes: { service_desk_ticket_id: ticket.id.to_s }
    }
    expect(native.response).to have_http_status(:ok), native.response.body
    message = Message.find(native.response.parsed_body.fetch('id'))
    attachment = message.attachments.sole
    native.get "#{timeline_path}/#{message.id}/attachments/#{attachment.id}", headers: native_headers
    expect(native.response).to have_http_status(:ok), native.response.body

    requester = ActionDispatch::Integration::Session.new(Rails.application)
    requester.post '/portal/session', params: {}, headers: sd_user.create_new_auth_token, as: :json
    expect(requester.response).to have_http_status(:ok)
    expect(requester.response.parsed_body.dig('context', 'id')).to eq(operator_grant.id.to_s)
    requester.get "/portal/api/chamados/#{ticket.id}/respostas/#{message.id}/anexos/#{attachment.id}"
    expect(requester.response).to have_http_status(:not_found)
  end
end
