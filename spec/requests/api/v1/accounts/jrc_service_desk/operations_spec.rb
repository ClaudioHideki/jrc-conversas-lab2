# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'JRC Service Desk CP4 HTTP operations', type: :request do
  include_context 'JRC Service Desk domain'
  include JrcServiceDeskLifecycleFixtures
  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token }
  def payload
    JSON.parse(response.body)
  end
  def request_headers(key = nil)
    key ? headers.merge('Idempotency-Key' => key) : headers
  end
  def create_over_http(key = 'cp4-request')
    post "#{base}/tickets", headers: request_headers(key), as: :json,
      params: { unit_id: sd_unit.id.to_s, ticket: sd_create_attributes }
  end

  it 'returns only real configured units and capabilities, never an admin bypass' do
    sd_status
    get "#{base}/ui_context", headers: headers
    expect(response).to have_http_status(:ok)
    expect(payload.values_at('contract_version', 'account_id', 'user_id', 'available')).to eq([1, sd_account.id.to_s, sd_user.id.to_s, true])
    expect(payload['units'].map { |u| u['id'] }).to eq([sd_unit.id.to_s])
    expect(payload['units'].first['operator_company']['id']).to eq(sd_operator.id.to_s)
    expect(payload['units'].first['initial_status']['id']).to eq(sd_status.id.to_s)
    expect(payload['capabilities']['settings']['index']).to be(false)
    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'does not invent an initial status or permit creation without configuration' do
    expect { get "#{base}/ui_context", headers: headers }.not_to change(JrcServiceDesk::TicketStatus, :count)
    expect(payload['units'].first['initial_status']).to be_nil
    expect(payload['units'].first['permissions']['create_ticket']).to be(false)
    expect(JrcServiceDesk::TicketStatus.where(account_id: sd_account.id).count).to eq(0)
  end

  it 'persists create, returns a real id, survives another GET and enters authorized lists and own queue' do
    expect { create_over_http }.to change(JrcServiceDesk::Ticket, :count).by(1)
    expect(response).to have_http_status(:created)
    id = payload.fetch('ticket_id')
    row = JrcServiceDesk::Ticket.find(id)
    expect(row.account_id).to eq(sd_account.id)
    expect(row.unit_id).to eq(sd_unit.id)
    expect(row.operator_company_id).to eq(sd_operator.id)
    get "#{base}/tickets/#{id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(payload.dig('ticket', 'title')).to eq(sd_create_attributes[:title])
    expect(payload.dig('ticket', 'number')).to eq(id)
    get "#{base}/tickets", headers: headers
    expect(payload['meta']['total']).to eq(1)
    expect(payload['items'].map { |v| v['id'] }).to eq([id])
    post "#{base}/tickets/#{id}/assign", headers: headers, as: :json,
      params: { assignment: { assignee_account_user_id: sd_account_user.id }, expected_lock_version: row.reload.lock_version }
    expect(response).to have_http_status(:ok)
    get "#{base}/tickets", headers: headers, params: { mine: 'true' }
    expect(payload['items'].map { |v| v['id'] }).to eq([id])
  end

  it 'repeats a creation key without duplicate tickets or creation context events' do
    create_over_http('same-key')
    first = payload.fetch('ticket_id')
    expect { create_over_http('same-key') }.not_to change(JrcServiceDesk::Ticket, :count)
    expect(payload.fetch('ticket_id')).to eq(first)
    expect(JrcServiceDesk::TicketEvent.where(ticket_id: first, event_type: 'creation_context_recorded').count).to eq(1)
  end

  it 'rejects a changed payload for the same key with no extra ticket' do
    create_over_http('bound-key')
    expect do
      post "#{base}/tickets", headers: request_headers('bound-key'), as: :json,
        params: { unit_id: sd_unit.id, ticket: sd_create_attributes.merge(title: 'Changed retry') }
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(response).to have_http_status(:conflict)
  end

  it 'requires a creation key and an explicit unit, not an automatic default' do
    expect do
      post "#{base}/tickets", headers: headers, as: :json, params: { unit_id: sd_unit.id, ticket: sd_create_attributes }
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect do
      post "#{base}/tickets", headers: request_headers('missing-unit'), as: :json, params: { ticket: sd_create_attributes }
    end.not_to change(JrcServiceDesk::Ticket, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JrcServiceDesk::Ticket.where(account_id: sd_account.id).count).to eq(0)
  end

  it 'updates title, description, priority and category, with a persisted history and reload' do
    row = sd_ticket
    priority = create(:jrc_sd_priority, unit: sd_unit)
    category = create(:jrc_sd_category, unit: sd_unit)
    patch "#{base}/tickets/#{row.id}", headers: headers, as: :json, params: {
      ticket: { title: 'Updated in HTTP', description: 'Updated description', priority_id: priority.id, category_id: category.id },
      expected_lock_version: row.lock_version
    }
    expect(response).to have_http_status(:ok)
    expect(row.reload.attributes.slice('title', 'description', 'priority_id', 'category_id')).to eq(
      'title' => 'Updated in HTTP', 'description' => 'Updated description', 'priority_id' => priority.id, 'category_id' => category.id)
    get "#{base}/tickets/#{row.id}", headers: headers
    expect(payload.dig('ticket', 'priority', 'id')).to eq(priority.id.to_s)
    get "#{base}/tickets/#{row.id}/events", headers: headers
    event = payload['items'].find { |v| v['event_type'] == 'ticket_updated' }
    expect(event.dig('data', 'title')).to eq(['Test ticket', 'Updated in HTTP'])
    expect(event.dig('author', 'id')).to eq(sd_account_user.id.to_s)
  end

  it 'rejects stale edits without silently replacing the newer value' do
    row = sd_ticket
    version = row.lock_version
    row.update!(title: 'Concurrent update')
    patch "#{base}/tickets/#{row.id}", headers: headers, as: :json,
      params: { ticket: { title: 'Stale update' }, expected_lock_version: version }
    expect(response).to have_http_status(:conflict)
    expect(row.reload.title).to eq('Concurrent update')
  end

  it 'transfers agent and queue only within the same explicit unit' do
    row = sd_ticket
    target = create(:account_user, account: sd_account, role: :agent)
    grant = create(:jrc_sd_membership, unit: sd_unit, account_user: target)
    team = create(:team, account: sd_account)
    queue = create(:jrc_sd_queue, unit: sd_unit, team: team)
    post "#{base}/tickets/#{row.id}/transfer", headers: headers, as: :json, params: {
      assignment: { assignee_account_user_id: target.id, queue_id: queue.id }, expected_lock_version: row.lock_version
    }
    expect(response).to have_http_status(:ok)
    expect(row.reload.assignee_membership_id).to eq(grant.id)
    expect(row.team_id).to eq(team.id)
    expect(row.unit_id).to eq(sd_unit.id)
    get "#{base}/tickets/#{row.id}", headers: headers
    expect(payload.dig('ticket', 'assignee', 'id')).to eq(target.id.to_s)
  end

  it 'changes working states only through an explicitly published D01 rule' do
    row = sd_ticket
    lc_publish
    working = lc_statuses[:working]
    post "#{base}/tickets/#{row.id}/work_status", headers: headers, as: :json,
      params: { status_id: working.id, expected_lock_version: row.lock_version }
    expect(response).to have_http_status(:ok)
    get "#{base}/tickets/#{row.id}", headers: headers
    expect(payload.dig('ticket', 'status', 'id')).to eq(working.id.to_s)
    expect(row.reload.status_id).to eq(working.id)
    expect(row.ticket_events.last.data.values_at('from_status_id', 'to_status_id')).to eq([sd_status.id, working.id])
  end

  %w[waiting resolved closed cancelled].each do |phase|
    it "does not allow the unresolved lifecycle transition to #{phase}" do
      row = sd_ticket
      target = create(:jrc_sd_status, unit: sd_unit, initial: false, phase: phase)
      post "#{base}/tickets/#{row.id}/work_status", headers: headers, as: :json,
        params: { status_id: target.id, expected_lock_version: row.lock_version }
      expect([403, 404, 422]).to include(response.status)
      expect(row.reload.status_id).to eq(sd_status.id)
      expect(row.ticket_events.count).to eq(0)
    end
  end

  it 'persists internal notes with the real actor and supports collection and item readback' do
    row = sd_ticket
    post "#{base}/tickets/#{row.id}/notes", headers: request_headers('note-key'), as: :json,
      params: { note: { body: 'Internal note from HTTP' } }
    expect(response).to have_http_status(:ok)
    note_id = payload.fetch('result_id')
    note = JrcServiceDesk::TicketNote.find(note_id)
    expect(note.author_membership_id).to eq(sd_membership.id)
    expect(note.visibility).to eq('internal')
    expect(note.created_at).to be_present
    get "#{base}/tickets/#{row.id}/notes/#{note_id}", headers: headers
    expect(payload.dig('item', 'body')).to eq('Internal note from HTTP')
    get "#{base}/tickets/#{row.id}/notes", headers: headers
    expect(payload['meta']['total']).to eq(1)
    expect(payload['items'].first.dig('author', 'id')).to eq(sd_account_user.id.to_s)
    post "#{base}/tickets/#{row.id}/notes", headers: request_headers('note-key'), as: :json,
      params: { note: { body: 'Internal note from HTTP' } }
    expect(response).to have_http_status(:ok)
    expect(row.ticket_notes.count).to eq(1)
  end

  it 'links an authorized native conversation and supports real item readback without copying messages' do
    sd_as_admin!
    row = sd_ticket
    conversation = create(:conversation, account: sd_account)
    before_messages = Message.count
    post "#{base}/tickets/#{row.id}/conversations", headers: headers, as: :json, params: { conversation_id: conversation.id }
    expect(response).to have_http_status(:ok)
    id = payload.fetch('result_id')
    get "#{base}/tickets/#{row.id}/conversations/#{id}", headers: headers
    expect(payload.dig('item', 'conversation_id')).to eq(conversation.id.to_s)
    expect(payload.dig('item', 'conversation_display_id')).to eq(conversation.display_id.to_s)
    expect(payload['item']).not_to have_key('messages')
    expect(Message.count).to eq(before_messages)
  end

  it 'returns pending operational SLA without raw conditions or fabricated deadlines' do
    row = sd_ticket
    sd_as_admin!
    JrcServiceDesk::RecordSlaSnapshotService.new(user_context: sd_context).call(ticket_id: row.id, attributes: sd_snapshot_attributes)
    sd_account_user.update!(role: :agent)
    get "#{base}/tickets/#{row.id}/sla", headers: headers
    expect(response).to have_http_status(:ok)
    expect(payload['items'].length).to eq(2)
    payload['items'].each do |item|
      expect(item.values_at('due_at', 'achieved_at', 'met', 'calculation_pending')).to eq([nil, nil, nil, true])
      expect(item.keys & %w[contract_conditions policy_conditions calendar_conditions]).to be_empty
    end
  end

  it 'distinguishes actual empty results, inaccessible records, and unavailable authentication' do
    get "#{base}/tickets", headers: headers
    expect(response).to have_http_status(:ok)
    expect(payload['items']).to eq([])
    expect(payload['meta']['total']).to eq(0)
    get "#{base}/tickets/9223372036854775807", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(payload['code']).to eq('not_found')
    get "#{base}/tickets"
    expect(response).to have_http_status(:unauthorized)
  end
end
