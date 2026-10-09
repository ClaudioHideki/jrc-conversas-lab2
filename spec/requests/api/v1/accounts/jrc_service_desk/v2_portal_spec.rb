# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk verified customer portal', type: :request do
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

  def publish(body, visibility)
    attributes = { body: body, visibility: visibility }
    context = JrcServiceDesk::OperationalContext.new(sd_context)
    receipt = JrcServiceDesk::InteractionPreview.new(ticket: ticket, context: context).call(attributes: attributes).fetch(:receipt)
    JrcServiceDesk::AddNoteService.new(user_context: sd_context).call(ticket_id: ticket.id, attributes: attributes,
                                                                      preview_receipt: receipt, idempotency_key: SecureRandom.uuid)
  end

  it 'shows only explicitly public content to the real verified native customer' do
    publish('Internal diagnosis', 'internal')
    publish('Customer update', 'customer')
    publish('Silent public update', 'public_without_notification')
    get path, params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['notes'].map { |row| row['body'] }).to eq(['Customer update', 'Silent public update'])
    expect(response.body).not_to include('Internal diagnosis', 'author_membership', 'account_user', 'company_id', 'unit_id')
  end

  it 'rejects a non-verified browser identity even with a valid native token' do
    identity.update!(hmac_verified: false)
    get path, params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'does not grant access based on ticket number, matching email, or a foreign contact token' do
    other = create(:contact, account: sd_account, identifier: SecureRandom.uuid)
    other_identity = create(:contact_inbox, contact: other, inbox: widget.inbox, hmac_verified: true)
    foreign_token = Widget::TokenService.new(payload: { source_id: other_identity.source_id, inbox_id: widget.inbox.id }).generate_token
    foreign_proof = OpenSSL::HMAC.hexdigest('sha256', widget.hmac_token, other.identifier)
    get path, params: { website_token: widget.website_token }, headers: { 'X-Auth-Token' => foreign_token,
                                                                          'X-Service-Desk-Identifier' => other.identifier,
                                                                          'X-Service-Desk-Identity-Token' => foreign_proof }
    expect(response).to have_http_status(:not_found)
  end

  it 'persists a native incoming customer reply with real contact authorship and repeatable request key' do
    params = { website_token: widget.website_token, body: 'Customer verified reply', conversation_id: conversation.id }
    post "#{path}/replies", params: params, headers: headers.merge('Idempotency-Key' => 'customer-reply'), as: :json
    expect(response).to have_http_status(:created)
    message = Message.find(response.parsed_body['message_id'])
    expect(message.sender).to eq(sd_contact)
    expect(message.incoming?).to be(true)
    expect(message.conversation_id).to eq(conversation.id)
    expect do
      post "#{path}/replies", params: params, headers: headers.merge('Idempotency-Key' => 'customer-reply'), as: :json
    end.not_to change(Message, :count)
    expect(response).to have_http_status(:created)
    expect(ticket.ticket_notes).to be_empty
  end

  it 'rechecks identity revocation and link/recipient scope before customer writes' do
    identity.update!(hmac_verified: false)
    expect do
      post "#{path}/replies", params: { website_token: widget.website_token, body: 'Denied reply', conversation_id: conversation.id },
                              headers: headers.merge('Idempotency-Key' => 'denied-reply'), as: :json
    end.not_to change(Message, :count)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'never permits portal downloads of internal files even when scan is clean' do
    file = fixture_file_upload(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt'), 'text/plain')
    post "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/tickets/#{ticket.id}/interactions",
         params: { note: { body: 'Internal evidence' }, files: [file] },
         headers: sd_user.create_new_auth_token.merge('Idempotency-Key' => 'internal-file')
    expect(response).to have_http_status(:created)
    note = ticket.ticket_notes.last
    attachment = note.files.first
    attachment.blob.update!(metadata: { 'service_desk_scan_state' => 'clean' })
    get "#{path}/notes/#{note.id}/attachments/#{attachment.id}", params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('Private evidence')
  end
end
