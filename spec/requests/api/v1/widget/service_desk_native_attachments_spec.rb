# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Native Widget downloads for Service Desk attachments', type: :request do
  include_context 'JRC Service Desk domain'

  let(:widget) { create(:channel_widget, account: sd_account) }
  let(:identity) { create(:contact_inbox, contact: sd_contact, inbox: widget.inbox, hmac_verified: false) }
  let(:conversation) { create(:conversation, account: sd_account, contact: sd_contact, inbox: widget.inbox, contact_inbox: identity) }
  let(:ticket) { sd_ticket }
  let(:message) { create(:message, account: sd_account, inbox: widget.inbox, conversation: conversation, sender: sd_contact) }
  let(:attachment) do
    message.attachments.create!(account: sd_account, file_type: :file,
                                file: { io: StringIO.new('Synthetic Widget evidence'), filename: 'evidence.txt', content_type: 'text/plain' })
  end
  let(:path) { "/api/v1/widget/messages/#{message.id}/attachments/#{attachment.id}" }
  let(:params) { { website_token: widget.website_token } }
  let(:headers) do
    { 'X-Auth-Token' => Widget::TokenService.new(payload: { source_id: identity.source_id, inbox_id: widget.inbox.id }).generate_token }
  end
  let(:clean_metadata) do
    { 'service_desk_scan_state' => 'clean', 'service_desk_scan_adapter' => 'clamav-instream-v1',
      'service_desk_scan_sha256' => Digest::SHA256.hexdigest('Synthetic Widget evidence'), 'service_desk_scanned_at' => Time.current.iso8601(6) }
  end

  before do
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
    attachment.file.blob.update!(metadata: attachment.file.blob.metadata.merge(clean_metadata))
  end

  [false, true].each do |verified|
    %w[incoming outgoing].each do |direction|
      it "streams an own public #{direction} attachment for a #{verified ? 'verified' : 'guest'} native identity without a User session" do
        identity.update!(hmac_verified: verified)
        message.update!(message_type: direction)

        get path, params: params, headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.body).to eq('Synthetic Widget evidence')
        expect(response.headers['Cache-Control']).to eq('no-store')
        expect(response.headers['Content-Disposition']).to include('attachment', 'evidence.txt')
        expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
        expect(response.headers['Location']).to be_nil
      end
    end
  end

  it 'does not authorize an attachment by its id outside the requested message' do
    other_message = create(:message, account: sd_account, inbox: widget.inbox, conversation: conversation)
    get "/api/v1/widget/messages/#{other_message.id}/attachments/#{attachment.id}", params: params, headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.headers['Cache-Control']).to eq('no-store')
  end

  it 'uses ActiveStorage serving policy for executable types instead of rendering them inline' do
    attachment.file.blob.update!(content_type: 'text/html')
    get path, params: params, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('application/octet-stream')
    expect(response.headers['Content-Security-Policy']).to include('sandbox')
  end

  it 'rejects a foreign Contact in the same Account and inbox' do
    other_contact = create(:contact, account: sd_account)
    foreign_identity = create(:contact_inbox, contact: other_contact, inbox: widget.inbox)
    foreign_headers = { 'X-Auth-Token' => Widget::TokenService.new(payload: {
      source_id: foreign_identity.source_id, inbox_id: widget.inbox.id
    }).generate_token }

    get path, params: params, headers: foreign_headers
    expect(response).to have_http_status(:not_found)
  end

  it 'rejects a valid JWT from another Account and widget' do
    foreign_widget = create(:channel_widget)
    foreign_identity = create(:contact_inbox, inbox: foreign_widget.inbox, contact: create(:contact, account: foreign_widget.account))
    foreign_headers = { 'X-Auth-Token' => Widget::TokenService.new(payload: {
      source_id: foreign_identity.source_id, inbox_id: foreign_widget.inbox.id
    }).generate_token }

    get path, params: { website_token: foreign_widget.website_token }, headers: foreign_headers
    expect(response).to have_http_status(:not_found)
  end

  it 'rejects a mismatched JWT inbox even when its source id is known in this widget' do
    mismatched = { 'X-Auth-Token' => Widget::TokenService.new(payload: {
      source_id: identity.source_id, inbox_id: create(:channel_widget, account: sd_account).inbox.id
    }).generate_token }

    get path, params: params, headers: mismatched
    expect(response).to have_http_status(:not_found)
  end

  it 'keeps guest conversations isolated even for another ContactInbox of the same Contact' do
    another_identity = create(:contact_inbox, contact: sd_contact, inbox: widget.inbox)
    another_headers = { 'X-Auth-Token' => Widget::TokenService.new(payload: {
      source_id: another_identity.source_id, inbox_id: widget.inbox.id
    }).generate_token }

    get path, params: params, headers: another_headers
    expect(response).to have_http_status(:not_found)
  end

  it 'follows the native verified conversation scope and rechecks verification on every request' do
    identity.update!(hmac_verified: true)
    another_identity = create(:contact_inbox, contact: sd_contact, inbox: widget.inbox, hmac_verified: true)
    another_headers = { 'X-Auth-Token' => Widget::TokenService.new(payload: {
      source_id: another_identity.source_id, inbox_id: widget.inbox.id
    }).generate_token }

    get path, params: params, headers: another_headers
    expect(response).to have_http_status(:ok)
    identity.update!(hmac_verified: false)
    get path, params: params, headers: another_headers
    expect(response).to have_http_status(:not_found)
  end

  it 'rejects a revoked native source id instead of reusing a prior download authorization' do
    old_headers = headers
    get path, params: params, headers: old_headers
    expect(response).to have_http_status(:ok)
    identity.update!(source_id: SecureRandom.uuid)
    get path, params: params, headers: old_headers
    expect(response).to have_http_status(:not_found)
    expect(response.headers['Cache-Control']).to eq('no-store')
  end

  it 'excludes private messages' do
    message.update!(private: true)
    get path, params: params, headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'excludes activity messages with the same filter as the native MessageFinder' do
    message.update!(message_type: :activity)
    get path, params: params, headers: headers
    expect(response).to have_http_status(:not_found)
  end

  [nil, 'pending', 'unavailable', 'infected'].each do |state|
    it "keeps scan state #{state.inspect} unavailable without redirecting or downloading bytes" do
      attachment.file.blob.update!(metadata: { 'service_desk_scan_state' => state })
      get path, params: params, headers: headers
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq('code' => 'attachment_scan_unavailable')
      expect(response.headers['Cache-Control']).to eq('no-store')
      expect(response.headers['Location']).to be_nil
    end
  end

  it 'does not make an anonymous signed ActiveStorage URL a Widget download authority' do
    get Rails.application.routes.url_helpers.rails_storage_redirect_path(attachment.file, only_path: true)
    expect(response).to have_http_status(:not_found)
    expect(response.headers['Cache-Control']).to eq('no-store')
  end

  it 'rejects a private Service Desk signed_id before persisting a Widget reattachment' do
    message.update!(private: true)
    blob = attachment.file.blob

    expect do
      post '/api/v1/widget/messages', params: params.merge(message: { content: 'Public reattachment', attachments: [blob.signed_id] }), headers: headers
    end.not_to change(conversation.messages, :count)
    expect(response).to have_http_status(:unprocessable_entity)

    get path, params: params, headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'denies every protected owner when a signed_id is also attached to an internal TicketNote' do
    sd_as_admin!
    uploaded = fixture_file_upload(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt'), 'text/plain')
    file = ActionDispatch::Http::UploadedFile.new(tempfile: uploaded.tempfile, filename: 'internal-evidence.txt', type: 'text/plain')
    note = JrcServiceDesk::AddNoteService.new(user_context: sd_context).call(
      ticket_id: ticket.id, attributes: { body: 'Internal note attachment' }, idempotency_key: 'widget-internal-note', files: [file]
    )
    blob = note.files.first.blob
    blob.update!(metadata: blob.metadata.merge(clean_metadata).merge('service_desk_scan_sha256' => Digest::SHA256.hexdigest(blob.download)))

    expect do
      post '/api/v1/widget/messages', params: params.merge(message: { content: 'Note reattachment', attachments: [blob.signed_id] }), headers: headers
    end.not_to change(conversation.messages, :count)
    expect(response).to have_http_status(:unprocessable_entity)

    get Rails.application.routes.url_helpers.rails_blob_path(note.files.first, only_path: true)
    expect(response).to have_http_status(:not_found)
  end

  it 'denies bytes reattached by signed_id from a protected Call recording' do
    skip 'Native enterprise calls unavailable' unless defined?(::Call)

    call = create(:call, conversation: conversation)
    call.recording.attach(attachment.file.blob)
    blob = attachment.file.blob
    expect do
      post '/api/v1/widget/messages', params: params.merge(message: { content: 'Call reattachment', attachments: [blob.signed_id] }), headers: headers
    end.not_to change(conversation.messages, :count)
    expect(response).to have_http_status(:unprocessable_entity)

    get path, params: params, headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'preserves a clean own public Widget signed_id reattachment and its authenticated download' do
    expect do
      post '/api/v1/widget/messages', params: params.merge(message: { content: 'Own public attachment', attachments: [attachment.file.blob.signed_id] }), headers: headers
    end.to change(conversation.messages, :count).by(1)
    expect(response).to have_http_status(:ok), response.body
    reattached = Message.find(response.parsed_body.fetch('id')).attachments.sole
    expect(reattached.file.blob_id).to eq(attachment.file.blob_id)
    get "/api/v1/widget/messages/#{reattached.message_id}/attachments/#{reattached.id}", params: params, headers: headers
    expect(response).to have_http_status(:ok), response.body
    expect(response.body).to eq('Synthetic Widget evidence')
  end

  it 'denies a shared blob with a public protected Message outside this native ContactInbox scope' do
    other_contact = create(:contact, account: sd_account)
    other_identity = create(:contact_inbox, contact: other_contact, inbox: widget.inbox)
    other_conversation = create(:conversation, account: sd_account, contact: other_contact, inbox: widget.inbox, contact_inbox: other_identity)
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: other_conversation)
    other_message = create(:message, account: sd_account, inbox: widget.inbox, conversation: other_conversation)
    other_message.attachments.create!(account: sd_account, file_type: :file, file: attachment.file.blob)

    get path, params: params, headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'denies a shared blob with a protected owner in another Account' do
    foreign_ticket = create(:jrc_sd_ticket)
    foreign_message = create(:message, account: foreign_ticket.account)
    create(:jrc_sd_conversation_link, ticket: foreign_ticket, conversation: foreign_message.conversation)
    foreign_message.attachments.create!(account: foreign_ticket.account, file_type: :file, file: attachment.file.blob)

    get path, params: params, headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'leaves an ordinary native attachment payload and download behavior unchanged' do
    ordinary = create(:message, :with_attachment, account: sd_account, inbox: widget.inbox)
    expect(ordinary.attachments.first.push_event_data).not_to have_key(:service_desk_protected)
    get "/api/v1/widget/messages/#{ordinary.id}/attachments/#{ordinary.attachments.first.id}", params: params, headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'marks only file payloads belonging to a same-Account Service Desk conversation' do
    expect(attachment.push_event_data).to include(service_desk_protected: true, filename: 'evidence.txt')
    external = message.attachments.create!(account: sd_account, file_type: :file, external_url: 'https://example.org/file.pdf')
    expect(external.push_event_data).not_to have_key(:service_desk_protected)
    attachment.account_id = create(:account).id
    expect(attachment.push_event_data).not_to have_key(:service_desk_protected)
  end
end
