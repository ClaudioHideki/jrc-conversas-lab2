# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Widget::ServiceDeskController, type: :request do
  include_context 'JRC Service Desk domain'
  let(:sd_contact) { create(:contact, account: sd_account, identifier: SecureRandom.uuid) }
  let(:widget) { create(:channel_widget, account: sd_account) }
  let(:identity) { create(:contact_inbox, contact: sd_contact, inbox: widget.inbox, hmac_verified: true) }
  let(:conversation) { create(:conversation, account: sd_account, contact: sd_contact, inbox: widget.inbox, contact_inbox: identity) }
  let(:ticket) { sd_ticket }
  let(:token) { Widget::TokenService.new(payload: { source_id: identity.source_id, inbox_id: widget.inbox.id }).generate_token }
  let(:headers) do
    { 'X-Auth-Token' => token, 'X-Service-Desk-Identifier' => sd_contact.identifier,
      'X-Service-Desk-Identity-Token' => OpenSSL::HMAC.hexdigest('sha256', widget.hmac_token, sd_contact.identifier) }
  end
  let(:path) { "/api/v1/widget/service_desk/tickets/#{ticket.id}" }

  before do
    sd_as_admin!
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
  end

  it 'reads back native customer attachment identifiers and gates their bytes on the scanner' do
    file = fixture_file_upload(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt'), 'text/plain')
    post "#{path}/replies",
         params: { website_token: widget.website_token, body: 'Verified evidence', conversation_id: conversation.id, files: [file] },
         headers: headers.merge('Idempotency-Key' => 'customer-evidence')
    expect(response).to have_http_status(:created)
    message = Message.find(response.parsed_body.fetch('message_id'))
    attachment = message.attachments.first
    get path, params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:ok)
    actual = response.parsed_body.fetch('replies').find { |row| row['id'] == message.id.to_s }
    expect(actual.fetch('attachments')).to eq(
      [{ 'id' => attachment.id.to_s, 'filename' => attachment.file.filename.to_s, 'scan_state' => 'unavailable' }]
    )
    expect(response.body).not_to include('blob_key', 'storage_url', 'account_user')
    download = "#{path}/messages/#{message.id}/attachments/#{attachment.id}"
    get download, params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:conflict)
    attachment.file.blob.update!(metadata: { 'service_desk_scan_state' => 'clean' })
    get download, params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq(File.read(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt')))
  end
end
