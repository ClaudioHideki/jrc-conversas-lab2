# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk creation in every enabled Account', type: :request do
  include_context 'JRC Service Desk domain'

  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token.merge('Idempotency-Key' => SecureRandom.uuid) }
  let(:request_data) { { unit_id: sd_unit.id, ticket: sd_create_attributes } }
  let(:second_admin) { create(:account_user, account: sd_foreign_account, role: :administrator) }
  let(:second_headers) { second_admin.user.create_new_auth_token.merge('Idempotency-Key' => SecureRandom.uuid) }

  before do
    sd_as_admin!
    sd_membership.update!(active: false)
    sd_foreign_account.enable_features!('jrc_service_desk')
  end

  it 'creates, rereads, lists and edits using the native administrator without activating an agent grant' do
    post "#{base}/tickets", params: request_data, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch('ticket_id')
    row = JrcServiceDesk::Ticket.find(id)
    actor = row.created_by_membership
    expect(actor).to have_attributes(account_id: sd_account.id, unit_id: sd_unit.id, account_user_id: sd_account_user.id,
                                    administrative_actor: true, active: false, availability: 'unavailable', capacity: nil, skills: [])
    expect(sd_membership.reload.active).to be(false)
    expect(sd_account_user.reload.role).to eq('administrator')
    expect(row.ticket_events.find_by!(event_type: 'ticket_created').actor_membership_id).to eq(actor.id)
    expect(row.ticket_events.where(event_type: 'creation_context_recorded').count).to eq(1)

    get "#{base}/tickets/#{id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('ticket', 'number')).to eq(id)
    get "#{base}/tickets", params: { unit_id: sd_unit.id, q: "##{id}" }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').map { |ticket| ticket['id'] }).to eq([id])
    patch "#{base}/tickets/#{id}", params: { ticket: { title: 'Administrator update' }, expected_lock_version: row.lock_version },
                                  headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(row.reload.title).to eq('Administrator update')
    expect(row.ticket_events.find_by!(event_type: 'ticket_updated').actor_membership.account_user_id).to eq(sd_account_user.id)
  end

  it 'creates in another active unit of its Account without a grant and rejects a foreign unit' do
    status = create(:jrc_sd_status, unit: sd_other_unit)
    priority = create(:jrc_sd_priority, unit: sd_other_unit)
    attributes = sd_create_attributes.merge(status_id: status.id, priority_id: priority.id)
    get "#{base}/ui_context", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['units'].map { |unit| unit['id'] }).to contain_exactly(sd_unit.id.to_s, sd_other_unit.id.to_s)
    expect(response.parsed_body['units'].all? { |unit| unit.dig('permissions', 'create_ticket') }).to be(true)
    post "#{base}/tickets", params: { unit_id: sd_other_unit.id, ticket: attributes }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    expect(JrcServiceDesk::Ticket.find(response.parsed_body.fetch('ticket_id')).unit_id).to eq(sd_other_unit.id)
    expect do
      post "#{base}/tickets", params: { unit_id: sd_foreign_unit.id, ticket: attributes }, headers: headers, as: :json
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(response).to have_http_status(:not_found)
  end

  it 'creates independently in a second newly enabled Account and denies cross-Account reads in both directions' do
    second_contact = create(:contact, account: sd_foreign_account)
    second_status = create(:jrc_sd_status, unit: sd_foreign_unit)
    second_priority = create(:jrc_sd_priority, unit: sd_foreign_unit)
    second_base = "/api/v1/accounts/#{sd_foreign_account.id}/jrc_service_desk"
    post "#{second_base}/tickets", params: { unit_id: sd_foreign_unit.id, ticket: { title: 'Second Account ticket', description: 'Fictitious only',
      requester_id: second_contact.id, status_id: second_status.id, priority_id: second_priority.id } }, headers: second_headers, as: :json
    expect(response).to have_http_status(:created)
    second_id = response.parsed_body.fetch('ticket_id')
    second_row = JrcServiceDesk::Ticket.find(second_id)
    expect(second_row).to have_attributes(account_id: sd_foreign_account.id, unit_id: sd_foreign_unit.id)
    expect(second_row.created_by_membership.account_user_id).to eq(second_admin.id)
    post "#{base}/tickets", params: request_data, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    first_id = response.parsed_body.fetch('ticket_id')
    get "#{base}/tickets/#{second_id}", headers: headers
    expect(response).to have_http_status(:not_found)
    get "#{second_base}/tickets/#{first_id}", headers: second_headers
    expect(response).to have_http_status(:not_found)
    get "#{base}/tickets", headers: second_headers
    expect(response.status).to be_in([401, 403, 404])
  end

  it 'replays the same creation even after the administrator gains an explicit operational binding' do
    post "#{base}/tickets", params: request_data, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch('ticket_id')
    sd_membership.update!(active: true)
    expect do
      post "#{base}/tickets", params: request_data, headers: headers, as: :json
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.fetch('ticket_id')).to eq(id)
    expect(JrcServiceDesk::Ticket.find(id).ticket_events.where(event_type: 'ticket_created').count).to eq(1)
  end

  it 'denies a demoted administrator despite retaining its audit actor and preserves the historical author' do
    post "#{base}/tickets", params: request_data, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch('ticket_id')
    actor = JrcServiceDesk::Ticket.find(id).created_by_membership
    sd_account_user.update!(role: :agent)
    get "#{base}/tickets/#{id}", headers: headers
    expect(response.status).to be_in([403, 404])
    expect do
      post "#{base}/tickets", params: request_data, headers: headers, as: :json
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(response.status).to be_in([403, 404])
    expect(actor.reload.active).to be(false)
    sd_membership.update!(active: true)
    get "#{base}/tickets/#{id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(actor.reload.active).to be(false)
    expect(JrcServiceDesk::TicketEvent.where(ticket_id: id, event_type: 'ticket_created').take!.actor_membership.account_user_id).to eq(sd_account_user.id)
  end

  it 'keeps audit-only actors out of assignees, capacity and the membership administration directory' do
    post "#{base}/tickets", params: request_data, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    row = JrcServiceDesk::Ticket.find(response.parsed_body.fetch('ticket_id'))
    context = JrcServiceDesk::OperationalContext.new(sd_context)
    assignees = JrcServiceDesk::CatalogQuery.new(user_context: sd_context, resource: 'assignees', parameters: { unit_id: sd_unit.id }).collection
    expect(assignees[:items]).to be_empty
    expect(JrcServiceDesk::StructurePolicy::Scope.new(sd_context, JrcServiceDesk::UnitMembership).resolve).not_to include(row.created_by_membership)
    row.assignee_membership = row.created_by_membership
    expect(row).not_to be_valid
    expect(row.errors[:assignee_membership]).to include('must be an operational unit grant')
    expect(context.actor_for(sd_unit).id).to eq(row.created_by_membership_id)
  end

  it 'does not write an administrative actor when reading an existing ticket composer' do
    creator = create(:jrc_sd_membership, unit: sd_unit)
    row = sd_ticket(created_by_membership: creator)
    get "#{base}/tickets/#{row.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect do
      JrcServiceDesk::ComposerProjection.new(ticket: row, context: JrcServiceDesk::OperationalContext.new(sd_context)).call
    end.not_to change(JrcServiceDesk::UnitMembership, :count)
  end

  it 'allows an agent with its explicit unit grant and denies creation in an ungranted unit' do
    sd_account_user.update!(role: :agent)
    sd_membership.update!(active: true)
    post "#{base}/tickets", params: request_data, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    expect(JrcServiceDesk::Ticket.find(response.parsed_body.fetch('ticket_id')).created_by_membership_id).to eq(sd_membership.id)
    expect do
      post "#{base}/tickets", params: { unit_id: sd_other_unit.id, ticket: sd_create_attributes }, headers: headers, as: :json
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(response).to have_http_status(:not_found)
  end

  it 'does not elevate a delegated custom role to native administrator scope' do
    role = create(:custom_role, account: sd_account, permissions: %w[jrc_service_desk_module_view jrc_service_desk_tickets_view
      jrc_service_desk_lookups_view jrc_service_desk_customers_view jrc_service_desk_tickets_create])
    sd_account_user.update!(custom_role: role)
    expect do
      post "#{base}/tickets", params: request_data, headers: headers, as: :json
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(response.status).to be_in([403, 404])
    expect(JrcServiceDesk::UnitMembership.where(administrative_actor: true, account_user: sd_account_user)).to be_empty
  end

  it 'requires a SuperAdmin to have explicit Account authorization and never borrows another Account unit' do
    staff = create(:super_admin)
    staff_headers = staff.create_new_auth_token.merge('Idempotency-Key' => SecureRandom.uuid)
    expect do
      post "#{base}/tickets", params: request_data, headers: staff_headers, as: :json
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(response.status).to be_in([401, 403, 404])
    membership = create(:account_user, account: sd_account, user: staff, role: :administrator)
    post "#{base}/tickets", params: request_data, headers: staff_headers, as: :json
    expect(response).to have_http_status(:created)
    expect(JrcServiceDesk::Ticket.find(response.parsed_body.fetch('ticket_id')).created_by_membership.account_user_id).to eq(membership.id)
    expect do
      post "#{base}/tickets", params: request_data.merge(unit_id: sd_foreign_unit.id), headers: staff_headers, as: :json
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(response).to have_http_status(:not_found)
  end

  it 'honors feature deactivation without creating a ticket or an audit actor' do
    sd_account.disable_features!('jrc_service_desk')
    expect do
      post "#{base}/tickets", params: request_data, headers: headers, as: :json
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(response).to have_http_status(:forbidden)
    expect(JrcServiceDesk::UnitMembership.where(account_user: sd_account_user, administrative_actor: true)).to be_empty
  end

  it 'rejects a missing description without issuing a protocol or retaining an audit actor' do
    expect do
      post "#{base}/tickets", params: request_data.merge(ticket: sd_create_attributes.merge(description: ' ')), headers: headers, as: :json
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).not_to have_key('ticket_id')
    expect(JrcServiceDesk::UnitMembership.where(account_user: sd_account_user, administrative_actor: true)).to be_empty
  end

  it 'rejects foreign contacts and unknown units without writing audit actors or tickets' do
    contact = create(:contact, account: sd_foreign_account)
    expect do
      post "#{base}/tickets", params: request_data.merge(ticket: sd_create_attributes.merge(requester_id: contact.id)), headers: headers, as: :json
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(response).to have_http_status(:not_found)
    expect do
      post "#{base}/tickets", params: request_data.merge(unit_id: 9_999_999_999), headers: headers, as: :json
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(response).to have_http_status(:not_found)
    expect(JrcServiceDesk::UnitMembership.where(account_user: sd_account_user, administrative_actor: true)).to be_empty
  end
end
