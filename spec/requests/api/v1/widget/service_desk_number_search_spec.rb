# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Verified portal official-number search', type: :request do
  include_context 'JRC Service Desk domain'
  let(:sd_contact) { create(:contact, account: sd_account, identifier: SecureRandom.uuid) }
  let(:widget) { create(:channel_widget, account: sd_account) }
  let(:identity) { create(:contact_inbox, contact: sd_contact, inbox: widget.inbox, hmac_verified: true) }
  let(:conversation) { create(:conversation, account: sd_account, contact: sd_contact, inbox: widget.inbox, contact_inbox: identity) }
  let(:ticket) { sd_ticket(title: 'Title does not include the ticket number') }
  let(:token) { Widget::TokenService.new(payload: { source_id: identity.source_id, inbox_id: widget.inbox.id }).generate_token }
  let(:headers) do
    { 'X-Auth-Token' => token, 'X-Service-Desk-Identifier' => sd_contact.identifier,
      'X-Service-Desk-Identity-Token' => OpenSSL::HMAC.hexdigest('sha256', widget.hmac_token, sd_contact.identifier) }
  end
  let(:path) { '/api/v1/widget/service_desk/tickets' }

  before do
    sd_as_admin!
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
  end

  [false, true].each do |prefix|
    it "finds an authorized official number #{prefix ? 'with' : 'without'} the hash prefix" do
      get path, params: { website_token: widget.website_token, q: "#{prefix ? '#' : ''}#{ticket.id}" }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('tickets').map { |row| row['id'] }).to eq([ticket.id.to_s])
    end
  end

  it 'never makes another customer ticket readable by knowing its exact number' do
    other = sd_ticket(requester: create(:contact, account: sd_account))
    get path, params: { website_token: widget.website_token, q: other.id.to_s }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('tickets')).to be_empty
  end

  it 'retains literal title search and rejects wildcard-based discovery' do
    get path, params: { website_token: widget.website_token, q: 'Title does not' }, headers: headers
    expect(response.parsed_body.fetch('tickets').map { |row| row['id'] }).to eq([ticket.id.to_s])
    get path, params: { website_token: widget.website_token, q: '%' }, headers: headers
    expect(response.parsed_body.fetch('tickets')).to be_empty
  end
end
