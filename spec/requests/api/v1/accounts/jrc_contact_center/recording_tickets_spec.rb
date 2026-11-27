# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Native recording-linked Ticket list and destination authority', :pabx do
  include_context 'with native manual recording ticket intake'

  def native_ticket
    JrcContactCenter::RecordingTicketIntake.new(account: account, member: member).call(
      recording_id: record.id, unit_id: sd_unit.id, attributes: ticket_input.fetch('ticket'), idempotency_key: SecureRandom.uuid
    )
  end

  def read_tickets(query = {}, recording_id = record.id)
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/recordings/#{recording_id}/tickets",
        headers: actor.create_new_auth_token, params: query
  end

  it 'returns only the native authorized title, status and route identity without exposing private origin or credentials' do
    ticket = native_ticket
    read_tickets
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body.slice('account_id', 'user_id', 'recording_id', 'call_session_id', 'call_id')).to eq(
      'account_id' => account.id.to_s, 'user_id' => actor.id.to_s, 'recording_id' => record.id.to_s,
      'call_session_id' => source_call.id.to_s, 'call_id' => source_call.external_session_id
    )
    row = body.fetch('items').sole
    expect(row.keys).to contain_exactly('id', 'number', 'title', 'status', 'status_phase')
    expect(row).to include('id' => ticket.id.to_s, 'title' => ticket.title)
    expect(response.headers.fetch('Cache-Control')).to include('private', 'no-store')
    expect(response.body).not_to include(ticket.description, ticket.idempotency_key, 'recording_origin', 'recording_reference')
    expect(provider).not_to have_received(:find_analysis)
  end

  it 'does not present an ordinary same-contact Ticket as a recording-linked Ticket' do
    JrcServiceDesk::CreateTicketWorkflowService.new(user_context: sd_context).call(
      unit_id: sd_unit.id, attributes: ticket_input.fetch('ticket'), idempotency_key: SecureRandom.uuid
    )
    read_tickets
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items')).to eq([])
    expect(response.parsed_body.fetch('meta')).to eq('page' => 1, 'per_page' => 20, 'total' => 0, 'pages' => 0)
  end

  it 'uses the original private origin after a mapping change without broadening destination visibility' do
    ticket = native_ticket
    business.update!(settings: business.settings.except('service_desk_unit_id'))
    read_tickets
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([ticket.id.to_s])
  end

  it 'keeps read access independent from the current creation permission' do
    ticket = native_ticket
    role.update!(permissions: role.permissions - ['jrc_service_desk_tickets_create'])
    read_tickets
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('items').pluck('id')).to eq([ticket.id.to_s])
  end

  %w[jrc_contact_center_recordings_listen jrc_service_desk_tickets_view].each do |right|
    it "denies the read after current #{right} authority is revoked" do
      ticket = native_ticket
      role.update!(permissions: role.permissions - [right])
      read_tickets
      expect(response).to have_http_status(:unauthorized)
      expect(response.body).not_to include(ticket.title)
      expect(JrcServiceDesk::Ticket.where(account: account).count).to eq(1)
    end
  end

  it 'does not leak destination titles or total after the destination unit membership is withdrawn' do
    ticket = native_ticket
    sd_membership.update!(active: false)
    read_tickets
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include(ticket.title)
  end

  it 'does not resolve a recording from another account even when its external call ID matches' do
    native_ticket
    foreign = record.dup
    foreign.account = sd_foreign_account
    foreign.save!
    read_tickets({}, foreign.id)
    expect(response).to have_http_status(:not_found)
  end

  it 'paginates twenty plus one native records without duplicate IDs or provider reads' do
    tickets = Array.new(21) { native_ticket }
    read_tickets
    first = response.parsed_body
    expect(response).to have_http_status(:ok)
    expect(first.fetch('items').length).to eq(20)
    expect(first.fetch('meta')).to eq('page' => 1, 'per_page' => 20, 'total' => 21, 'pages' => 2)
    read_tickets({ page: 2 })
    second = response.parsed_body
    expect(second.fetch('items').length).to eq(1)
    expect((first.fetch('items') + second.fetch('items')).pluck('id')).to eq(tickets.reverse.map { |ticket| ticket.id.to_s })
    expect(provider).not_to have_received(:find_analysis)
  end

  it 'rejects unsupported account, actor and unit selectors instead of treating them as scope' do
    native_ticket
    read_tickets({ user_id: actor.id, unit_id: sd_unit.id, account_id: sd_foreign_account.id })
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'rejects malformed pagination without clamping it into an authorized page' do
    native_ticket
    read_tickets({ page: '0' })
    expect(response).to have_http_status(:unprocessable_entity)
  end
  it 'rejects a nonempty JSON GET body instead of silently accepting hidden selectors' do
    native_ticket
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/recordings/#{record.id}/tickets",
        headers: actor.create_new_auth_token, params: { unit_id: sd_unit.id }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'invalid_recording_ticket_page')
  end
end
