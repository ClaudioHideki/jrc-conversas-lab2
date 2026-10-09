# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk atomic claim HTTP boundary', type: :request do
  include_context 'JRC Service Desk domain'
  let(:path) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/claim_next" }
  let(:headers) { sd_user.create_new_auth_token.merge('Idempotency-Key' => 'http-claim') }

  it 'returns a sanitized real dependency when availability or capacity is absent' do
    ticket = sd_ticket
    post path, params: { unit_id: sd_unit.id }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('code' => 'operational_dependency_unavailable')
    expect(ticket.reload.assignee_membership_id).to be_nil
    expect(ticket.ticket_events.where(event_type: 'ticket_claimed')).to be_empty
    sd_membership.update!(availability: 'available')
    post path, params: { unit_id: sd_unit.id }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(ticket.reload.assignee_membership_id).to be_nil
  end

  it 'claims exactly one authorized ticket and replays the same claim' do
    sd_membership.update!(availability: 'available', capacity: 1)
    ticket = sd_ticket
    post path, params: { unit_id: sd_unit.id }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.values_at('applied', 'operation', 'account_id',
                                          'ticket_id')).to eq([true, 'claim_next', sd_account.id.to_s, ticket.id.to_s])
    expect(ticket.reload.assignee_membership_id).to eq(sd_membership.id)
    expect(response.parsed_body['assignee_account_user_id']).to eq(sd_account_user.id.to_s)
    expect do
      post path, params: { unit_id: sd_unit.id }, headers: headers, as: :json
    end.not_to change(ticket.ticket_events.where(event_type: 'ticket_claimed'), :count)
  end

  it 'independently reads back the actual claimed assignment' do
    sd_membership.update!(availability: 'available', capacity: 1)
    ticket = sd_ticket
    post path, params: { unit_id: sd_unit.id }, headers: headers, as: :json
    get "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/tickets/#{ticket.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('ticket', 'unit_id')).to eq(sd_unit.id.to_s)
    expect(response.parsed_body.dig('ticket', 'assignee')).to be_present
  end

  it 'rejects a unit without an operational grant and does not claim an unrelated ticket' do
    sd_as_admin!
    sd_membership.update!(availability: 'available', capacity: 1)
    ticket = sd_ticket
    post path, params: { unit_id: sd_other_unit.id }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(ticket.reload.assignee_membership_id).to be_nil
  end
end
