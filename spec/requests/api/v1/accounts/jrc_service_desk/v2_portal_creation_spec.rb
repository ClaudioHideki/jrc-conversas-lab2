# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk portal creation with real configured authority', type: :request do
  include_context 'JRC Service Desk domain'
  let(:sd_contact) { create(:contact, account: sd_account, identifier: SecureRandom.uuid) }
  let(:widget) { create(:channel_widget, account: sd_account) }
  let(:identity) { create(:contact_inbox, contact: sd_contact, inbox: widget.inbox, hmac_verified: true) }
  let(:token) { Widget::TokenService.new(payload: { source_id: identity.source_id, inbox_id: widget.inbox.id }).generate_token }
  let(:headers) do
    { 'X-Auth-Token' => token, 'Idempotency-Key' => 'portal-create', 'X-Service-Desk-Identifier' => sd_contact.identifier,
      'X-Service-Desk-Identity-Token' => OpenSSL::HMAC.hexdigest('sha256', widget.hmac_token, sd_contact.identifier) }
  end
  let(:service) do
    JrcServiceDesk::Service.create!(account: sd_account, unit: sd_unit, code: 'portal-test', name: 'Customer support', active: true,
                                    default_priority: sd_priority, portal_inbox: widget.inbox, portal_execution_membership: sd_membership,
                                    form_fields: [{ 'key' => 'circuit', 'label' => 'Circuit', 'type' => 'text', 'required' => true }])
  end
  let(:base) { '/api/v1/widget/service_desk' }
  let(:attributes) do
    { service_id: service.id, service_revision: JrcServiceDesk::ConfigurationResources.revision('services', service),
      title: 'Verified customer request', description: 'Circuit unavailable', service_fields: { circuit: 'TEST-CIRCUIT' } }
  end

  before do
    sd_as_admin!
    sd_status
  end

  it 'keeps portal creation OFF and exposes no internal authority in the published catalogue' do
    expect(service.portal_enabled?).to be(false)
    get "#{base}/services", params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['services']).to be_empty
    expect do
      post "#{base}/tickets", params: { website_token: widget.website_token, ticket: attributes }, headers: headers, as: :json
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(response).to have_http_status(:not_found)
    service.update!(portal_enabled: true)
    get "#{base}/services", params: { website_token: widget.website_token }, headers: headers
    expect(response.parsed_body['services'].first['name']).to eq(service.name)
    expect(response.body).not_to include('execution_membership', 'unit_id', 'account_user', 'inbox_id')
  end

  context 'with a real request created through the configured member' do
    let(:values) { attributes }

    before do
      service.update!(portal_enabled: true)
      post "#{base}/tickets", params: { website_token: widget.website_token, ticket: values }, headers: headers, as: :json
    end

    it 'records the actual customer, creator, channel and configured service fields' do
      expect(response).to have_http_status(:created)
      ticket = JrcServiceDesk::Ticket.find(response.parsed_body.dig('ticket', 'id'))
      expect(ticket.created_by_membership).to eq(sd_membership)
      expect(ticket.requester).to eq(sd_contact)
      expect(ticket.origin_channel).to eq('portal')
      expect(ticket.service_fields).to eq('circuit' => 'TEST-CIRCUIT')
    end

    it 'records the native contact, incoming authorship, linked conversation and immutable request' do
      ticket = JrcServiceDesk::Ticket.find(response.parsed_body.dig('ticket', 'id'))
      request = JrcServiceDesk::PortalRequest.find_by!(ticket: ticket)
      expect(request.contact_inbox).to eq(identity)
      expect(request.message.sender).to eq(sd_contact)
      expect(request.message.incoming?).to be(true)
      expect(ticket.ticket_conversations.first.conversation).to eq(request.conversation)
      expect { request.update!(request_key: 'edited') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it 'replays the committed request without another ticket, request or outgoing message' do
      ticket = JrcServiceDesk::Ticket.find(response.parsed_body.dig('ticket', 'id'))
      request = JrcServiceDesk::PortalRequest.find_by!(ticket: ticket)
      expect do
        post "#{base}/tickets", params: { website_token: widget.website_token, ticket: values }, headers: headers, as: :json
      end.not_to change(JrcServiceDesk::Ticket, :count)
      expect(response).to have_http_status(:created)
      expect(response.parsed_body.dig('ticket', 'id')).to eq(ticket.id.to_s)
      expect(JrcServiceDesk::PortalRequest.where(account: sd_account).count).to eq(1)
      expect(request.conversation.messages.where(message_type: :outgoing)).to be_empty
    end
  end

  it 'rejects forged unit, assignee, requester or status fields without creating a partial request' do
    service.update!(portal_enabled: true)
    %w[unit_id requester_id assignee_account_user_id status_id].each do |key|
      post "#{base}/tickets", params: { website_token: widget.website_token, ticket: attributes.merge(key => 1) }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(JrcServiceDesk::PortalRequest.where(account: sd_account).count).to eq(0)
    expect(JrcServiceDesk::Ticket.where(account: sd_account).count).to eq(0)
  end

  it 'rechecks policy version and real executor revocation before retrying a committed request' do
    service.update!(portal_enabled: true)
    values = attributes
    post "#{base}/tickets", params: { website_token: widget.website_token, ticket: values }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    service.update!(description: 'Revised customer catalogue')
    post "#{base}/tickets", params: { website_token: widget.website_token, ticket: values }, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    sd_membership.update!(active: false)
    post "#{base}/tickets", params: { website_token: widget.website_token, ticket: values }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(JrcServiceDesk::PortalRequest.where(account: sd_account).count).to eq(1)
  end

  it 'rejects a revoked identity and a service from another widget' do
    service.update!(portal_enabled: true)
    other_widget = create(:channel_widget, account: sd_account)
    other_identity = create(:contact_inbox, contact: sd_contact, inbox: other_widget.inbox, hmac_verified: true)
    other_token = Widget::TokenService.new(payload: { source_id: other_identity.source_id, inbox_id: other_widget.inbox.id }).generate_token
    post "#{base}/tickets", params: { website_token: other_widget.website_token, ticket: attributes },
                            headers: headers.merge('X-Auth-Token' => other_token,
                                                   'X-Service-Desk-Identity-Token' => OpenSSL::HMAC.hexdigest('sha256', other_widget.hmac_token,
                                                                                                              sd_contact.identifier)), as: :json
    expect(response).to have_http_status(:not_found)
    identity.update!(hmac_verified: false)
    post "#{base}/tickets", params: { website_token: widget.website_token, ticket: attributes }, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(JrcServiceDesk::Ticket.where(account: sd_account).count).to eq(0)
  end

  it 'accepts only real native customer uploads and protects their download with identity and scan checks' do
    service.update!(portal_enabled: true)
    file = fixture_file_upload(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt'), 'text/plain')
    post "#{base}/tickets", params: { website_token: widget.website_token, ticket: attributes.to_json, files: [file] }, headers: headers
    expect(response).to have_http_status(:created)
    request = JrcServiceDesk::PortalRequest.where(account: sd_account).last
    attachment = request.message.attachments.first
    path = "#{base}/tickets/#{request.ticket_id}/messages/#{request.message_id}/attachments/#{attachment.id}"
    get path, params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:conflict)
    attachment.file.blob.update!(metadata: { 'service_desk_scan_state' => 'clean' })
    get path, params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.headers['Content-Disposition']).to include('attachment')
    identity.update!(hmac_verified: false)
    get path, params: { website_token: widget.website_token }, headers: headers
    expect(response).to have_http_status(:unauthorized)
  end
end
