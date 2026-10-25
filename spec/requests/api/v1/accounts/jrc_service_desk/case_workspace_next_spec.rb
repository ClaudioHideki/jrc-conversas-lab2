# frozen_string_literal: true

require 'rails_helper'

# Native integration specifications supplied for the Codex runtime.
# NOT executed in the ZIP author's environment; requires the additive migration.
RSpec.describe 'Service Desk incident and problem workspaces', type: :request do
  include_context 'JRC Service Desk domain'

  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/case_workspaces" }
  let(:headers) { sd_user.create_new_auth_token }

  before { sd_as_admin! }

  def create_case(kind: 'incident', key: SecureRandom.uuid)
    post base, headers: headers.merge('Idempotency-Key' => key), as: :json,
               params: { unit_id: sd_unit.id, record: { resource_kind: kind, title: "Synthetic #{kind}", severity: 'normal' } }
    expect(response).to have_http_status(:created), response.body
    JrcServiceDesk::Incident.find(response.parsed_body.dig('record', 'id'))
  end

  def command_case(row, action, values = {}, key: SecureRandom.uuid, version: nil)
    post "#{base}/#{row.id}/commands", headers: headers.merge('Idempotency-Key' => key), as: :json,
                                       params: { action: action, attributes: values, expected_lock_version: version || row.reload.lock_version }
  end

  it 'creates once, preserves the native record identity and replays without duplicate journal entries' do
    row = create_case(key: 'case-workspace-create')
    expect(create_case(key: 'case-workspace-create').id).to eq(row.id)
    expect(row.incident_entries.where(event_type: 'created').count).to eq(1)
    get "#{base}/#{row.id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('record', 'title')).to eq('Synthetic incident')
  end

  it 'returns integral totals before pagination and does not mix incidents with problems' do
    3.times { create_case }
    create_case(kind: 'problem')
    get base, headers: headers, params: { unit_id: sd_unit.id, kind: 'incident', page: 1, per_page: 1 }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('meta', 'total')).to eq(3)
    expect(response.parsed_body.fetch('items').size).to eq(1)
  end

  it 'rejects stale edits while preserving the confirmed update' do
    row = create_case
    original_version = row.lock_version
    command_case(row, 'update', { title: 'Confirmed synthetic title' }, version: original_version)
    expect(response).to have_http_status(:ok)
    command_case(row, 'update', { title: 'Stale title' }, version: original_version)
    expect(response).to have_http_status(:conflict)
    expect(row.reload.title).to eq('Confirmed synthetic title')
  end

  it 'links and unlinks tickets without changing their operational status or SLA snapshots' do
    row = create_case
    ticket = sd_ticket
    before = ticket.attributes.slice('status_id', 'opened_at', 'resolved_at', 'closed_at', 'lifecycle_policy_version_id')
    command_case(row, 'link_tickets', { ids: [ticket.id] }, key: 'case-link-once')
    expect(response).to have_http_status(:ok)
    command_case(row, 'link_tickets', { ids: [ticket.id] }, key: 'case-link-once')
    expect(response).to have_http_status(:ok)
    expect(row.case_links.active.where(ticket_id: ticket.id).count).to eq(1)
    expect(ticket.reload.attributes.slice(*before.keys)).to eq(before)
    command_case(row, 'unlink_ticket', { id: ticket.id })
    expect(response).to have_http_status(:ok)
    expect(JrcServiceDesk::Ticket.exists?(ticket.id)).to be(true)
    expect(ticket.reload.attributes.slice(*before.keys)).to eq(before)
  end

  it 'links a problem to an incident without changing the incident state' do
    incident = create_case
    problem = create_case(kind: 'problem')
    command_case(problem, 'link_incidents', { ids: [incident.id] })
    expect(response).to have_http_status(:ok)
    expect(incident.reload.status).to eq('open')
    get "#{base}/#{incident.id}/related", headers: headers, params: { type: 'incidents', linked: 'true' }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').map { |item| item.fetch('id').to_s }).to include(problem.id.to_s)
  end

  it 'requires a real solution and closes only the selected record' do
    row = create_case
    ticket = sd_ticket
    command_case(row, 'link_tickets', { ids: [ticket.id] })
    expect(response).to have_http_status(:ok)
    ticket_status = ticket.reload.status_id
    command_case(row, 'transition', { status: 'resolved', resolution: '' })
    expect(response).to have_http_status(:unprocessable_entity)
    command_case(row, 'transition', { status: 'resolved', resolution: 'Synthetic verified correction' })
    expect(response).to have_http_status(:ok)
    command_case(row, 'transition', { status: 'closed' })
    expect(response).to have_http_status(:ok)
    expect(row.reload.status).to eq('closed')
    expect(ticket.reload.status_id).to eq(ticket_status)
    expect(row.incident_entries.where(event_type: 'transitioned').count).to eq(2)
  end

  it 'records internal commentary and safely rejects an empty comment' do
    row = create_case
    command_case(row, 'comment', { body: 'Synthetic internal note' })
    expect(response).to have_http_status(:ok)
    expect(row.incident_entries.find_by!(event_type: 'note_added').data['visibility']).to eq('internal')
    count = row.incident_entries.count
    command_case(row, 'comment', { body: ' ' })
    expect(response).to have_http_status(:unprocessable_entity)
    expect(row.incident_entries.count).to eq(count)
  end

  it 'rejects a foreign unit without creating a record' do
    count = JrcServiceDesk::Incident.count
    post base, headers: headers.merge('Idempotency-Key' => 'foreign-case'), as: :json,
               params: { unit_id: sd_foreign_unit.id, record: { resource_kind: 'incident', title: 'Foreign synthetic record', severity: 'normal' } }
    expect(response).to have_http_status(:not_found)
    expect(JrcServiceDesk::Incident.count).to eq(count)
  end

  it 'uses one authorized linked-ticket filter for incidents and their related problems' do
    incident = create_case
    problem = create_case(kind: 'problem')
    unrelated = create_case
    ticket = sd_ticket(origin_channel: 'manual')
    command_case(incident, 'link_tickets', { ids: [ticket.id] })
    expect(response).to have_http_status(:ok)
    command_case(problem, 'link_incidents', { ids: [incident.id] })
    expect(response).to have_http_status(:ok)
    %w[incident problem].each do |kind|
      get base, headers: headers, params: { unit_id: sd_unit.id, kind: kind, requester_id: sd_contact.id, source: 'manual' }
      expect(response).to have_http_status(:ok), response.body
      expect(response.parsed_body.fetch('items').map { |row| row['id'] }).to eq([(kind == 'incident' ? incident : problem).id.to_s])
      expect(response.parsed_body.dig('metrics', 'total')).to eq(1)
    end
    get base, headers: headers, params: { unit_id: sd_unit.id, kind: 'incident', source: 'email' }
    expect(response.parsed_body.dig('meta', 'total')).to eq(0)
    expect(unrelated.reload.status).to eq('open')
  end

  it 'does not cascade problem resolution or closure into linked incidents or tickets' do
    incident = create_case
    problem = create_case(kind: 'problem')
    ticket = sd_ticket
    command_case(incident, 'link_tickets', { ids: [ticket.id] })
    expect(response).to have_http_status(:ok)
    command_case(problem, 'link_incidents', { ids: [incident.id] })
    expect(response).to have_http_status(:ok)
    frozen = ticket.reload.attributes
    command_case(problem, 'transition', { status: 'resolved', resolution: 'Synthetic verified root cause and correction' })
    expect(response).to have_http_status(:ok)
    command_case(problem, 'transition', { status: 'closed' })
    expect(response).to have_http_status(:ok)
    expect(problem.reload.status).to eq('closed')
    expect(incident.reload.status).to eq('open')
    expect(ticket.reload.attributes).to eq(frozen)
  end

  it 'intersects the ticket picker requester, origin, phase and inclusive calendar period without writes' do
    row = create_case
    ticket = sd_ticket(origin_channel: 'whatsapp', created_at: Time.zone.parse('2026-10-24 10:00:00'))
    sd_ticket(requester: create(:contact, account: sd_account), origin_channel: 'whatsapp')
    sd_ticket(origin_channel: 'email')
    get "#{base}/#{row.id}/related", headers: headers, params: {
      type: 'tickets', linked: 'false', requester_id: sd_contact.id,
      source: 'whatsapp', phase: 'open', created_from: '2026-10-24', created_to: '2026-10-24'
    }
    expect(response).to have_http_status(:ok), response.body
    expect(response.parsed_body.fetch('items').map { |item| item['id'] }).to eq([ticket.id.to_s])
    expect(row.case_links.count).to eq(0)
    expect(ticket.reload.incident_id).to be_nil
  end

  it 'rejects foreign requester and inverted date filters without exposing or changing tickets' do
    row = create_case
    ticket = sd_ticket
    before = ticket.attributes
    foreign = create(:contact, account: sd_foreign_account)
    get "#{base}/#{row.id}/related", headers: headers, params: { type: 'tickets', requester_id: foreign.id }
    expect(response).to have_http_status(:not_found)
    get "#{base}/#{row.id}/related", headers: headers, params: { type: 'tickets', created_from: '2026-10-25', created_to: '2026-10-24' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(ticket.reload.attributes).to eq(before)
    expect(row.case_links.count).to eq(0)
  end

  it 'preserves N:N incident creation links and the original legacy pointer for the same ticket' do
    ticket = sd_ticket
    first = JrcServiceDesk::CreateIncidentService.new(user_context: sd_context).call(unit_id: sd_unit.id,
                                                                                     attributes: { title: 'First synthetic incident', severity: 'normal', ticket_ids: [ticket.id] }, idempotency_key: 'first-inc')
    second = JrcServiceDesk::CreateIncidentService.new(user_context: sd_context).call(unit_id: sd_unit.id,
                                                                                      attributes: { title: 'Second synthetic incident', severity: 'high', ticket_ids: [ticket.id] }, idempotency_key: 'second-inc')
    expect(ticket.reload.incident_id).to eq(first.id)
    context = JrcServiceDesk::OperationalContext.new(sd_context)
    expect(JrcServiceDesk::CaseAssociations.for_ticket(ticket, context).pluck(:id).sort).to eq([first.id, second.id].sort)
  end

  it 'denies unauthenticated and ordinary agents without case or journal writes' do
    row = create_case
    count = row.incident_entries.count
    get "#{base}/#{row.id}"
    expect(response).to have_http_status(:unauthorized)
    sd_account_user.update!(role: :agent)
    command_case(row, 'update', { title: 'Forbidden edit' })
    expect(response).to have_http_status(:not_found)
    expect(row.reload.title).to eq('Synthetic incident')
    expect(row.incident_entries.count).to eq(count)
  end
end
