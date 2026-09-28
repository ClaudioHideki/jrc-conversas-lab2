# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'CP5 native integrations', type: :request do
  include_context 'JRC Service Desk domain'
  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:row) { sd_ticket }

  it 'returns explicit backend capabilities in ui_context' do
    get "#{base}/ui_context", headers: headers
    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    expect(json.dig('capabilities', 'module', 'index')).to be(true)
    expect(json['effective_permissions']).to include('jrc_service_desk_tickets_view')
    expect(json['effective_permissions']).not_to include('jrc_service_desk_lifecycle_policies_manage')
  end

  it 'returns native customer identity without creating another contact' do
    row
    count = Contact.count
    get "#{base}/tickets/#{row.id}/customer_context", headers: headers
    expect(response).to have_http_status(:ok)
    result = JSON.parse(response.body)
    expect(result.dig('contact', 'id')).to eq(sd_contact.id.to_s)
    expect(result['contact'].keys.sort).to eq(%w[account_id id name])
    expect(Contact.count).to eq(count)
  end

  it 'denies customer projection after a membership revocation or flag disable' do
    row
    sd_membership.update!(active: false)
    get "#{base}/tickets/#{row.id}/customer_context", headers: headers
    expect(response).to have_http_status(:forbidden)
    sd_membership.update!(active: true)
    sd_account.disable_features!('jrc_service_desk')
    get "#{base}/tickets/#{row.id}/customer_context", headers: headers
    expect(response).to have_http_status(:forbidden)
  end

  it 'denies a foreign ticket and does not reveal its customer' do
    foreign = create(:jrc_sd_ticket, unit: sd_foreign_unit)
    get "#{base}/tickets/#{foreign.id}/customer_context", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'does not expose a Company from another Account on a malformed native contact' do
    skip 'Native Company extension unavailable' unless defined?(::Company) && sd_contact.respond_to?(:company_id)
    foreign = Company.create!(account: sd_foreign_account, name: 'Foreign company secret')
    sd_contact.update_columns(company_id: foreign.id) # Deliberate test-only corruption.
    get "#{base}/tickets/#{row.id}/customer_context", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include('Foreign company secret')
  end

  it 'returns the native conversation display_id only after both domain policies authorize' do
    sd_as_admin!
    conversation = create(:conversation, account: sd_account)
    link = JrcServiceDesk::LinkConversationService.new(user_context: sd_context).call(ticket_id: row.id, conversation_id: conversation.id)
    get "#{base}/tickets/#{row.id}/conversations/#{link.id}/navigation", headers: headers
    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    expect(json.dig('route', 'name')).to eq('inbox_conversation')
    expect(json.dig('route', 'params', 'conversation_id')).to eq(conversation.display_id.to_s)
    expect(json['conversation_id']).to eq(conversation.id.to_s)
    sd_account_user.update!(role: :agent)
    get "#{base}/tickets/#{row.id}/conversations/#{link.id}/navigation", headers: headers
    expect(response).to have_http_status(:forbidden)
  end

  it 'rejects unrelated link IDs and manipulated IDs' do
    %w[01 bogus 999999999999999999999999999].each do |bad_id|
      get "#{base}/tickets/#{row.id}/conversations/#{bad_id}/navigation", headers: headers
      expect([404, 422]).to include(response.status)
    end
    other = sd_ticket(title: 'Another ticket')
    sd_as_admin!
    conversation = create(:conversation, account: sd_account)
    link = JrcServiceDesk::LinkConversationService.new(user_context: sd_context).call(ticket_id: other.id, conversation_id: conversation.id)
    get "#{base}/tickets/#{row.id}/conversations/#{link.id}/navigation", headers: headers
    expect(response).to have_http_status(:not_found)
  end
  it 'refuses creation with a Contact from a different Account' do
    foreign = create(:contact, account: sd_foreign_account)
    post "#{base}/tickets", params: { unit_id: sd_unit.id,
      ticket: sd_create_attributes.merge(requester_id: foreign.id) },
      headers: headers.merge('Idempotency-Key' => SecureRandom.uuid), as: :json
    expect(response).to have_http_status(:not_found)
    expect(JrcServiceDesk::Ticket.count).to eq(0)
  end

  it 'does not expose context to an Account other than the native membership' do
    sd_foreign_account.enable_features!('jrc_service_desk')
    get "/api/v1/accounts/#{sd_foreign_account.id}/jrc_service_desk/ui_context", headers: headers
    expect([401, 403, 404]).to include(response.status)
    expect(response.body).not_to include('jrc_service_desk_tickets_create')
  end

end
