# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk current customer identity proof', type: :request do
  include_context 'JRC Service Desk domain'
  let(:widget) { create(:channel_widget, account: sd_account, hmac_mandatory: true) }
  let(:sd_contact) { create(:contact, :with_email, account: sd_account, identifier: SecureRandom.uuid) }
  let(:identity) { create(:contact_inbox, contact: sd_contact, inbox: widget.inbox, hmac_verified: true) }
  let(:token) { Widget::TokenService.new(payload: { source_id: identity.source_id, inbox_id: widget.inbox.id }).generate_token }
  let(:proof) { OpenSSL::HMAC.hexdigest('sha256', widget.hmac_token, sd_contact.identifier) }
  let(:headers) { { 'X-Auth-Token' => token, 'X-Service-Desk-Identifier' => sd_contact.identifier, 'X-Service-Desk-Identity-Token' => proof } }
  let(:base) { '/api/v1/widget/service_desk' }

  it 'requires a current HMAC on every portal request even when the native verification flag and token remain valid' do
    get "#{base}/tickets", params: { website_token: widget.website_token }, headers: headers.except('X-Service-Desk-Identity-Token')
    expect(response).to have_http_status(:forbidden)
    get "#{base}/services", params: { website_token: widget.website_token }, headers: headers.merge('X-Service-Desk-Identity-Token' => '0' * 64)
    expect(response).to have_http_status(:forbidden)
    get "#{base}/tickets", params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(proof, widget.hmac_token, 'identifier_hash', 'Identity-Token')
  end

  [false, true].each do |customer_master|
    context "with the native email-only merge and customer master #{customer_master}" do
      let(:source_identifier) { sd_contact.identifier }
      let(:stale_headers) { headers.dup }
      let(:recipient) { create(:contact, :with_email, account: sd_account, identifier: SecureRandom.uuid) }
      let(:recipient_identity) { create(:contact_inbox, contact: recipient, inbox: widget.inbox, hmac_verified: true) }
      let(:conversation) { create(:conversation, account: sd_account, inbox: widget.inbox, contact: recipient, contact_inbox: recipient_identity) }
      let(:ticket) { sd_ticket(requester: recipient, title: 'B confidential customer ticket', description: 'B confidential description') }
      let(:identifier_edit) do
        # Master blocks distinct nonblank identifiers. The real authorized edit
        # clears A's identifier while the native verification flag remains set.
        sd_as_admin!
        patch "/api/v1/accounts/#{sd_account.id}/contacts/#{sd_contact.id}", params: { identifier: nil },
                                                                             headers: sd_user.create_new_auth_token, as: :json
        { response: response, identifier: sd_contact.reload.identifier, hmac_verified: identity.reload.hmac_verified? }
      end

      before do
        sd_account.enable_features!('jrc_customer_master') if customer_master
        source_identifier
        stale_headers
        create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
        identifier_edit if customer_master
        patch '/api/v1/widget/contact', params: { website_token: widget.website_token, email: recipient.email },
                                        headers: { 'X-Auth-Token' => token }, as: :json
      end

      if customer_master
        it 'performs the authorized identifier edit without clearing native verification' do
          expect(identifier_edit[:response]).to have_http_status(:ok)
          expect(identifier_edit[:identifier]).to be_nil
          expect(identifier_edit[:hmac_verified]).to be(true)
        end
      end

      it 'moves the native browser identity to B while keeping the verification flag and changing the identifier' do
        expect(response).to have_http_status(:ok)
        expect(identity.reload.contact_id).to eq(recipient.id)
        expect(identity.hmac_verified?).to be(true)
        expect(recipient.reload.identifier).not_to eq(source_identifier)
      end

      it "denies A's token and stale proof for details, listing and replies" do
        get "#{base}/tickets/#{ticket.id}", params: { website_token: widget.website_token }, headers: stale_headers
        expect(response).to have_http_status(:forbidden)
        expect(response.body).not_to include(ticket.title, ticket.description, recipient.identifier)
        get "#{base}/tickets", params: { website_token: widget.website_token }, headers: stale_headers.except('X-Service-Desk-Identity-Token')
        expect(response).to have_http_status(:forbidden)
        expect(response.body).not_to include(ticket.title)
        expect do
          post "#{base}/tickets/#{ticket.id}/replies",
               params: { website_token: widget.website_token, body: 'Forged customer reply', conversation_id: conversation.id },
               headers: stale_headers.merge('Idempotency-Key' => 'stale-customer-proof'), as: :json
        end.not_to change(Message, :count)
        expect(response).to have_http_status(:forbidden)
      end

      it 'accepts the current proof for B and reads back the real customer ticket' do
        current_headers = stale_headers.merge('X-Service-Desk-Identifier' => recipient.identifier,
                                              'X-Service-Desk-Identity-Token' => OpenSSL::HMAC.hexdigest('sha256',
                                                                                                         widget.hmac_token, recipient.identifier))
        get "#{base}/tickets/#{ticket.id}", params: { website_token: widget.website_token }, headers: current_headers
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig('ticket', 'id')).to eq(ticket.id.to_s)
      end
    end
  end

  it 'preserves the native Master guard for distinct identifiers and independently denies portal access without a current proof' do
    sd_account.enable_features!('jrc_customer_master')
    source_headers = headers.dup
    recipient = create(:contact, :with_email, account: sd_account, identifier: SecureRandom.uuid)
    recipient_identity = create(:contact_inbox, contact: recipient, inbox: widget.inbox, hmac_verified: true)
    conversation = create(:conversation, account: sd_account, inbox: widget.inbox, contact: recipient, contact_inbox: recipient_identity)
    ticket = sd_ticket(requester: recipient, title: 'Protected B ticket')
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
    patch '/api/v1/widget/contact', params: { website_token: widget.website_token, email: recipient.email },
                                    headers: { 'X-Auth-Token' => token }, as: :json
    expect(response).to have_http_status(:ok)
    expect(identity.reload.contact_id).to eq(sd_contact.id)
    get "#{base}/tickets/#{ticket.id}", params: { website_token: widget.website_token },
                                        headers: source_headers.except('X-Service-Desk-Identity-Token')
    expect(response).to have_http_status(:forbidden)
    get "#{base}/tickets/#{ticket.id}", params: { website_token: widget.website_token }, headers: source_headers
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(ticket.title)
  end

  it 'rejects a proof signed by a different widget and keeps the new credential filtered from request logs' do
    other_widget = create(:channel_widget, account: sd_account)
    other_proof = OpenSSL::HMAC.hexdigest('sha256', other_widget.hmac_token, sd_contact.identifier)
    get "#{base}/tickets", params: { website_token: widget.website_token }, headers: headers.merge('X-Service-Desk-Identity-Token' => other_proof)
    expect(response).to have_http_status(:forbidden)
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    expect(filter.filter('HTTP_X_SERVICE_DESK_IDENTITY_TOKEN' => proof)).to eq('HTTP_X_SERVICE_DESK_IDENTITY_TOKEN' => '[FILTERED]')
    expect(filter.filter('identifier_hash' => proof)).to eq('identifier_hash' => '[FILTERED]')
    expect(filter.filter('contact' => { 'identifier' => sd_contact.identifier, 'identifier_hash' => proof }))
      .to eq('contact' => { 'identifier' => sd_contact.identifier, 'identifier_hash' => '[FILTERED]' })
  end
end
