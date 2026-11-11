# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Employee-only Service Desk and Portal boundary', type: :request do
  include_context 'JRC Service Desk domain'

  let(:support_user) { create(:user) }
  let(:support_account_user) { create(:account_user, account: sd_account, user: support_user, role: :agent) }
  let(:support_membership) { create(:jrc_sd_membership, unit: sd_unit, account_user: support_account_user, manual_assignment_enabled: true) }
  let(:team) { create(:team, account: sd_account) }
  let(:queue) { create(:jrc_sd_queue, unit: sd_unit, team: team, distribution_mode: 'manual') }
  let(:company) { JrcCustomers::Company.create!(account: sd_account, name: 'Private other customer') }
  let(:customer) { create(:contact, account: sd_account, company_id: company.id) }
  let(:customer_ticket) { sd_ticket(requester: customer, company_id: company.id, title: 'Other customer confidential', team: team, queue: queue) }
  let(:customer_service) { JrcServiceDesk::Service.create!(account: sd_account, unit: sd_unit, code: 'customer-private', name: 'Other customer catalogue', active: true) }
  let(:sd_priority) { create(:jrc_sd_priority, unit: sd_unit, code: 'normal', name: 'Normal') }
  let(:headers) { sd_user.create_new_auth_token }
  let(:path) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:portal_path) { "/portal/employee/accounts/#{sd_account.id}" }
  let(:opening) { { unit_id: sd_unit.id.to_s, ticket: { title: 'Internal employee request', description: 'Internal evidence', service_fields: {} } } }

  before do
    sd_account.enable_features!('jrc_customer_master')
    sd_priority
    sd_status
    support_membership
    TeamMember.create!(team: team, user: support_user)
    values = { 'queue_id' => queue.id, 'assignee_account_user_id' => support_account_user.id,
               'observer_account_user_id' => support_account_user.id, 'employee_isolation_enabled' => true,
               'employee_account_user_ids' => [sd_account_user.id, support_account_user.id],
               'support_account_user_ids' => [support_account_user.id], 'internal_service_ids' => [] }
    sd_account.update!(internal_attributes: sd_account.internal_attributes.merge(
      'requester_portal_enabled' => true, JrcServiceDesk::InternalIntake::KEY => { sd_unit.id.to_s => values }))
  end

  it 'forces employee identity and internal routing even when the client omits the mode flag' do
    post "#{path}/tickets", params: opening, headers: headers.merge('Idempotency-Key' => 'employee-native'), as: :json
    expect(response).to have_http_status(:created)
    ticket = JrcServiceDesk::Ticket.find(response.parsed_body.fetch('ticket_id'))
    expect(ticket.requester.email).to eq(sd_user.email)
    expect(ticket.company_id).to be_nil
    expect(ticket.assignee_membership_id).to eq(support_membership.id)
    expect(ticket.ticket_events.find_by!(event_type: 'creation_context_recorded').data['internal_request']).to be(true)
  end

  it 'rejects a forged company/requester and an external service ID instead of widening the employee request' do
    post "#{path}/tickets", params: opening.deep_merge(internal_request: false, ticket: { company_id: company.id, requester_id: customer.id }),
                               headers: headers.merge('Idempotency-Key' => 'employee-forged'), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post "#{path}/tickets", params: opening.merge(service_id: customer_service.id),
                               headers: headers.merge('Idempotency-Key' => 'employee-service-forged'), as: :json
    expect(response).to have_http_status(:forbidden)
    expect(JrcServiceDesk::Ticket.where(account: sd_account)).to be_empty
  end

  it 'does not list, count or open a customer ticket even when it was originally created by the same employee' do
    foreign = customer_ticket
    post "#{path}/tickets", params: opening, headers: headers.merge('Idempotency-Key' => 'employee-own'), as: :json
    expect(response).to have_http_status(:created)
    own_id = response.parsed_body.fetch('ticket_id').to_s
    get "#{path}/tickets", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([own_id])
    expect(response.parsed_body.dig('meta', 'total')).to eq(1)
    get "#{path}/tickets/#{foreign.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(foreign.title)
  end

  it 'keeps legitimate support access in the native app but restricts that same support identity in the employee Portal' do
    foreign = customer_ticket
    support_headers = support_user.create_new_auth_token
    get "#{path}/tickets/#{foreign.id}", headers: support_headers
    expect(response).to have_http_status(:ok)
    post '/portal/session', params: {}, headers: support_headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to have_key('employee_context')
    get "#{portal_path}/tickets/#{foreign.id}"
    expect(response).to have_http_status(:not_found)
    get '/portal/api/chamados'
    expect(response).to have_http_status(:forbidden)
  end

  it 'uses the existing login and HttpOnly cookie without granting any external company context' do
    post '/portal/session', params: {}, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('employee_context', 'user_id')).to eq(sd_user.id.to_s)
    expect(response.parsed_body).not_to have_key('contexts')
    expect(response.headers['access-token']).to be_nil
    cookie = Array(response.headers['Set-Cookie']).find { |value| value.start_with?('_jrc_requester_portal=') }
    expect(cookie).to include('httponly')
    expect(JrcServiceDesk::PortalGrant.where(user: sd_user)).to be_empty
    post "#{portal_path}/tickets", params: opening, headers: { 'Idempotency-Key' => 'employee-portal' }, as: :json
    expect(response).to have_http_status(:created)
  end

  it 'keeps the catalogue empty for unapproved services and denies direct service-ID access' do
    row = customer_service
    get "#{path}/service_definitions", params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to be_empty
    get "#{path}/catalogue_form", params: { unit_id: sd_unit.id, service_id: row.id }, headers: headers
    expect(response).to have_http_status(:forbidden)
  end

  it 'does not expose customer or establishment pickers to an employee through direct native URLs' do
    get "#{path}/establishments", params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:forbidden)
    get "#{path}/requester_people", params: { unit_id: sd_unit.id, company_id: company.id }, headers: headers
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include(company.name)
  end

  it 'fails closed for a new or removed roster member instead of reverting to unrestricted customer access' do
    values = sd_account.reload.internal_attributes.deep_dup
    values[JrcServiceDesk::InternalIntake::KEY][sd_unit.id.to_s]['employee_account_user_ids'].delete(sd_account_user.id)
    sd_account.update!(internal_attributes: values)
    get "#{path}/tickets/#{customer_ticket.id}", headers: headers
    expect(response).to have_http_status(:not_found)
    post "#{path}/tickets", params: opening, headers: headers.merge('Idempotency-Key' => 'employee-removed'), as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'does not let an external native User without the account membership enter the employee endpoints' do
    visitor = create(:user)
    get "#{portal_path}/ui_context", headers: visitor.create_new_auth_token
    expect([401, 403, 404]).to include(response.status)
    expect(response.body).not_to include('employee_account_user_ids', 'internal_service_ids')
  end
end
