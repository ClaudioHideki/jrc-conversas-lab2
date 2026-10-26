# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Untrusted direct upload Service Desk scan metadata', type: :request do
  include_context 'JRC Service Desk domain'

  let(:widget) { create(:channel_widget, account: sd_account) }
  let(:identity) { create(:contact_inbox, contact: sd_contact, inbox: widget.inbox, hmac_verified: false) }
  let(:conversation) { create(:conversation, account: sd_account, inbox: widget.inbox, contact: sd_contact, contact_inbox: identity) }
  let(:ticket) { sd_ticket }
  let(:bytes) { 'Synthetic unscanned direct upload bytes' }
  let(:widget_headers) do
    { 'X-Auth-Token' => Widget::TokenService.new(payload: { source_id: identity.source_id, inbox_id: widget.inbox.id }).generate_token }
  end
  let(:forged_metadata) do
    { identified: true, analyzed: true, composed: true, custom_tag: 'ordinary metadata retained',
      service_desk_scan_state: 'clean', service_desk_scan_adapter: 'clamav-instream-v1',
      service_desk_scan_sha256: Digest::SHA256.hexdigest(bytes), service_desk_scanned_at: Time.current.iso8601(6),
      service_desk_scan_future_verdict: 'trusted' }
  end

  before do
    create(:inbox_member, inbox: widget.inbox, user: sd_user)
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
  end

  %w[widget account].each do |entry|
    it "discards every scan proof supplied to the #{entry} direct upload and queues the real attachment as unavailable" do
      native_headers = sd_user.create_new_auth_token
      direct_path = if entry == 'widget'
                      '/api/v1/widget/direct_uploads'
                    else
                      "/api/v1/accounts/#{sd_account.id}/conversations/#{conversation.display_id}/direct_uploads"
                    end
      headers = entry == 'widget' ? widget_headers : native_headers
      post direct_path, headers: headers, as: :json, params: {
        website_token: widget.website_token,
        blob: { filename: 'unscanned.txt', byte_size: bytes.bytesize, checksum: Digest::MD5.base64digest(bytes),
                content_type: 'text/plain', metadata: forged_metadata }
      }
      expect(response).to have_http_status(:success), response.body
      payload = response.parsed_body
      blob = ActiveStorage::Blob.find_signed!(payload.fetch('signed_id'))
      expect(blob.metadata).to include('custom_tag' => 'ordinary metadata retained')
      expect(blob.metadata.keys.grep(/\Aservice_desk_scan_/)).to be_empty
      expect(blob.metadata).not_to have_key('service_desk_scanned_at')
      expect(JrcServiceDesk::AttachmentScanner.clean?(blob)).to be(false)

      direct_upload = payload.fetch('direct_upload')
      put direct_upload.fetch('url'), params: bytes, headers: direct_upload.fetch('headers')
      expect(response).to have_http_status(:success), response.body

      scan_calls = []
      allow(JrcServiceDesk::MessageAttachmentScanJob).to receive(:perform_later).and_wrap_original do |original, *arguments|
        scan_calls << { arguments: arguments, callers: caller.grep(%r{/(?:app/|active_storage/|active_record/)}).first(40) }
        original.call(*arguments)
      end
      if entry == 'widget'
        post '/api/v1/widget/messages', headers: widget_headers,
                                       params: { website_token: widget.website_token, message: { content: 'Own unscanned file', attachments: [blob.signed_id] } }
      else
        post "/api/v1/accounts/#{sd_account.id}/conversations/#{conversation.display_id}/messages", headers: native_headers, as: :json,
                                                                                                  params: { content: 'Own unscanned file', message_type: 'outgoing', private: false, attachments: [blob.signed_id] }
      end
      expect(response).to have_http_status(:ok), response.body
      message = Message.find(response.parsed_body.fetch('id'))
      attachment = message.attachments.sole
      expect(scan_calls.map { |call| call[:arguments] }).to eq([[attachment.id]]), scan_calls.inspect
      expect(JrcServiceDesk::MessageAttachmentScanJob).to have_been_enqueued.with(attachment.id).exactly(:once)
      expect(attachment.file.blob_id).to eq(blob.id)
      expect(blob.reload.metadata).to include('service_desk_scan_state' => 'unavailable', 'custom_tag' => 'ordinary metadata retained')
      expect(blob.metadata).not_to have_key('service_desk_scan_future_verdict')
      expect(JrcServiceDesk::AttachmentScanner.clean?(blob)).to be(false)

      get "/api/v1/widget/messages/#{message.id}/attachments/#{attachment.id}", headers: widget_headers,
                                                                            params: { website_token: widget.website_token }
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['code']).to eq('attachment_scan_unavailable')
    end
  end
end
