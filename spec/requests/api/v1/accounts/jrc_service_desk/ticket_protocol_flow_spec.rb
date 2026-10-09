# frozen_string_literal: true

require 'rails_helper'

# Native Rails/PostgreSQL acceptance path. Run only in an isolated test database.
RSpec.describe 'Service Desk ticket protocol and assigned-agent readback', type: :request do
  include_context 'JRC Service Desk domain'

  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token.merge('Idempotency-Key' => SecureRandom.uuid) }
  let(:agent) { create(:account_user, account: sd_account, role: :agent) }
  let(:agent_membership) { create(:jrc_sd_membership, unit: sd_unit, account_user: agent) }
  let(:queue) { create(:jrc_sd_queue, unit: sd_unit, distribution_mode: 'manual') }

  before { sd_as_admin! }

  it 'returns the persisted protocol and the selected agent on independent GET, list, and agent My queue' do
    agent_membership
    attributes = sd_create_attributes.merge(queue_id: queue.id, assignee_account_user_id: agent.id)
    post "#{base}/tickets", params: { unit_id: sd_unit.id, ticket: attributes }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    identifier = response.parsed_body.fetch('ticket_id')
    row = JrcServiceDesk::Ticket.find(identifier)
    expect(row.id).to be_positive
    expect(row.assignee_membership_id).to eq(agent_membership.id)

    get "#{base}/tickets/#{identifier}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('ticket')).to include('id' => identifier, 'number' => identifier)
    expect(response.parsed_body.dig('ticket', 'assignee', 'id')).to eq(agent.id.to_s)

    get "#{base}/tickets", params: { unit_id: sd_unit.id, q: "##{identifier}" }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').map { |item| item['number'] }).to eq([identifier])

    get "#{base}/tickets", params: { unit_id: sd_unit.id, mine: 'true', q: identifier }, headers: agent.user.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').map { |item| item['id'] }).to eq([identifier])
    expect(row.reload.id.to_s).to eq(identifier)
  end

  it 'replays the same creation without allocating a second ticket, protocol, or creation event' do
    request = { unit_id: sd_unit.id, ticket: sd_create_attributes }
    post "#{base}/tickets", params: request, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    identifier = response.parsed_body.fetch('ticket_id')
    expect do
      post "#{base}/tickets", params: request, headers: headers, as: :json
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.fetch('ticket_id')).to eq(identifier)
    expect(JrcServiceDesk::Ticket.find(identifier).ticket_events.where(event_type: 'ticket_created').count).to eq(1)
  end

  it 'rejects changed input under the same creation key without silently allocating a new protocol' do
    request = { unit_id: sd_unit.id, ticket: sd_create_attributes }
    post "#{base}/tickets", params: request, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    identifier = response.parsed_body.fetch('ticket_id')
    expect do
      post "#{base}/tickets", params: request.merge(ticket: request[:ticket].merge(title: 'Changed')), headers: headers, as: :json
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(response).to have_http_status(:conflict)
    expect(JrcServiceDesk::Ticket.find(identifier).title).to eq(request[:ticket][:title])
  end

  it 'does not return a protocol when creation validation fails' do
    expect do
      post "#{base}/tickets", params: { unit_id: sd_unit.id, ticket: sd_create_attributes.merge(title: '') }, headers: headers, as: :json
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).not_to have_key('ticket_id')
  end

  it 'accepts paired impact and urgency on the real API with a published matrix' do
    definition = { 'rules' => [{ 'key' => 'wide-urgent', 'precedence' => 1,
                               'match' => { 'impact' => 'wide', 'urgency' => 'urgent' },
                               'output' => { 'priority_id' => sd_priority.id } }] }
    JrcServiceDesk::PublishOperationalRulesService.new(user_context: sd_context).call(
      unit_id: sd_unit.id, kind: 'priority_matrix', definition: definition, enabled: true, expected_version: 0
    )
    request = { unit_id: sd_unit.id, ticket: sd_create_attributes.except(:priority_id).merge(impact_code: 'wide', urgency_code: 'urgent') }
    post "#{base}/tickets", params: request, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    identifier = response.parsed_body.fetch('ticket_id')
    get "#{base}/tickets/#{identifier}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('ticket')).to include('number' => identifier, 'impact_code' => 'wide', 'urgency_code' => 'urgent')
    expect(response.parsed_body.dig('ticket', 'priority', 'id')).to eq(sd_priority.id.to_s)
  end

  it 'never replaces an explicitly assigned agent with a round-robin candidate' do
    agent_membership
    queue.update!(distribution_mode: 'round_robin')
    other = create(:jrc_sd_membership, unit: sd_unit, availability: 'available', capacity: 20)
    attributes = sd_create_attributes.merge(queue_id: queue.id, assignee_account_user_id: agent.id)
    post "#{base}/tickets", params: { unit_id: sd_unit.id, ticket: attributes }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    row = JrcServiceDesk::Ticket.find(response.parsed_body.fetch('ticket_id'))
    expect(row.reload.assignee_membership_id).to eq(agent_membership.id)
    expect(row.assignee_membership_id).not_to eq(other.id)
    expect(row.ticket_events.where(event_type: 'ticket_auto_routed')).to be_empty
  end

  it 'auto-routes to a configured eligible agent and exposes the same ticket in My queue' do
    agent_membership.update!(availability: 'available', capacity: 10)
    queue.update!(distribution_mode: 'round_robin')
    attributes = sd_create_attributes.merge(queue_id: queue.id)
    post "#{base}/tickets", params: { unit_id: sd_unit.id, ticket: attributes }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    identifier = response.parsed_body.fetch('ticket_id')
    expect(JrcServiceDesk::Ticket.find(identifier).assignee_membership_id).to eq(agent_membership.id)
    get "#{base}/tickets", params: { unit_id: sd_unit.id, mine: 'true', q: "##{identifier}" }, headers: agent.user.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').map { |item| item['number'] }).to eq([identifier])
  end

  it 'preserves an unassigned ticket and its protocol when no automatic candidate is eligible' do
    queue.update!(distribution_mode: 'round_robin')
    attributes = sd_create_attributes.merge(queue_id: queue.id)
    post "#{base}/tickets", params: { unit_id: sd_unit.id, ticket: attributes }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    identifier = response.parsed_body.fetch('ticket_id')
    get "#{base}/tickets/#{identifier}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('ticket', 'number')).to eq(identifier)
    expect(response.parsed_body.dig('ticket', 'assignee')).to be_nil
  end

  it 'rejects an assignee outside the current unit without committing a ticket' do
    create(:jrc_sd_membership, unit: sd_other_unit, account_user: agent)
    attributes = sd_create_attributes.merge(assignee_account_user_id: agent.id)
    expect do
      post "#{base}/tickets", params: { unit_id: sd_unit.id, ticket: attributes }, headers: headers, as: :json
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).not_to have_key('ticket_id')
  end

  it 'does not expose another unit when its number is known' do
    row = sd_ticket(unit: sd_other_unit, status: create(:jrc_sd_status, unit: sd_other_unit),
                    priority: create(:jrc_sd_priority, unit: sd_other_unit), created_by_membership: create(:jrc_sd_membership, unit: sd_other_unit))
    get "#{base}/tickets", params: { unit_id: sd_unit.id, q: "##{row.id}" }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to be_empty
    get "#{base}/tickets/#{row.id}", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'retains the number on update and revokes agent access without deleting the ticket' do
    agent_membership
    row = sd_ticket(assignee_membership: agent_membership)
    patch "#{base}/tickets/#{row.id}", params: { ticket: { title: 'Updated title' }, expected_lock_version: row.lock_version }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    get "#{base}/tickets/#{row.id}", headers: headers
    expect(response.parsed_body.dig('ticket', 'number')).to eq(row.id.to_s)
    agent_membership.update!(active: false)
    get "#{base}/tickets/#{row.id}", headers: agent.user.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).not_to have_key('ticket')
    expect(row.reload.title).to eq('Updated title')
  end
end
