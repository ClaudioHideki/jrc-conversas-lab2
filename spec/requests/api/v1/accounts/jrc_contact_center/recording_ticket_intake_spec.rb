# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Native manual Service Desk intake from an authorized recording', :pabx do
  include_context 'with native manual recording ticket intake'

  def post_ticket(input = ticket_input, key = ticket_key)
    post "/api/v1/accounts/#{account.id}/jrc_service_desk/tickets",
         headers: actor.create_new_auth_token.merge('Idempotency-Key' => key), params: input, as: :json
  end

  def tickets
    JrcServiceDesk::Ticket.where(account: account)
  end

  def remove_right!(right)
    role.update!(permissions: role.permissions - [right])
  end

  it 'uses the native requester, current actor and existing append-only context event without exposing recording credentials' do
    post_ticket
    expect(response).to have_http_status(:created)
    ticket = tickets.sole
    expect(ticket).to have_attributes(unit_id: sd_unit.id, requester_id: sd_contact.id, created_by_membership_id: sd_membership.id)
    origin = ticket.ticket_events.find_by!(event_type: 'creation_context_recorded').data.fetch('recording_origin')
    expect(origin).to eq('schema_version' => 1, 'recording_id' => record.id, 'call_session_id' => source_call.id,
                         'call_id' => source_call.external_session_id,
                         'contact_id' => sd_contact.id, 'unit_id' => unit.id, 'queue_id' => queue.id,
                         'issuer_company_id' => company.id, 'business_unit_id' => business.id)
    expect(response.parsed_body.fetch('ticket_id')).to eq(ticket.id.to_s)
    expect(response.body).not_to include('recording_reference', 'synthetic-password', record.external_unique_id)
  end

  it 'replays an identical explicit request once and preserves the original native events' do
    post_ticket
    first = response.parsed_body
    post_ticket
    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to eq(first)
    expect(tickets.count).to eq(1)
    expect(tickets.sole.ticket_events.where(event_type: 'creation_context_recorded').count).to eq(1)
  end

  it 'saves the human review without completing the existing pending Ticket or changing its native event history' do
    post_ticket
    expect(response).to have_http_status(:created)
    ticket = tickets.sole
    before = ticket.attributes
    events = ticket.ticket_events.order(:id).pluck(:id)
    snapshot = JrcContactCenter::QualityAnalysisSnapshot.new(analysis: analysis, authorized_call_id: record.external_unique_id)
    input = { 'classification' => 'negative', 'adjusted_summary' => 'SYNTHETIC only the analysis review is completed',
              'adjusted_themes' => [], 'recommendation_ids' => [], 'justification' => 'SYNTHETIC Ticket remains pending',
              'expected_revision' => 0, 'expected_source_sha256' => snapshot.sha256, 'request_id' => SecureRandom.uuid }
    post "/api/v1/accounts/#{account.id}/jrc_contact_center/recordings/#{record.id}/quality_review",
         headers: actor.create_new_auth_token, params: { quality_review: input }, as: :json
    expect(response).to have_http_status(:ok)
    expect(ticket.reload.attributes).to eq(before)
    expect(ticket.ticket_events.order(:id).pluck(:id)).to eq(events)
  end

  it 'rejects an altered title with the same key without creating a second ticket' do
    post_ticket
    altered = ticket_input.deep_dup
    altered.fetch('ticket')['title'] = 'SYNTHETIC conflicting second title'
    post_ticket(altered)
    expect(response).to have_http_status(:conflict)
    expect(tickets.count).to eq(1)
  end

  it 'does not reuse an ordinary native intake as a recording-bound receipt' do
    post_ticket(ticket_input.except('recording_id'))
    expect(response).to have_http_status(:created)
    post_ticket
    expect(response).to have_http_status(:conflict)
    expect(tickets.sole.ticket_events.find_by!(event_type: 'creation_context_recorded').data).not_to have_key('recording_origin')
  end

  %w[jrc_contact_center_recordings_listen jrc_contact_center_operate contact_manage jrc_service_desk_tickets_create].each do |right|
    it "revalidates the current #{right} authority before creating a ticket" do
      remove_right!(right)
      post_ticket
      expect(response).to have_http_status(:forbidden)
      expect(tickets).to be_empty
    end
  end

  it 'does not obtain an explicit missing recording right from native administrator status' do
    member.update!(role: :administrator)
    remove_right!('jrc_contact_center_recordings_listen')
    post_ticket
    expect(response).to have_http_status(:forbidden)
    expect(tickets).to be_empty
  end

  it 'revalidates the destination membership on an existing native receipt without losing its history' do
    post_ticket
    expect(response).to have_http_status(:created)
    sd_membership.update!(active: false)
    post_ticket
    expect(response).to have_http_status(:not_found)
    expect(tickets.count).to eq(1)
  end

  it 'rejects another currently authorized unit when it differs from the native source mapping' do
    create(:jrc_sd_membership, unit: sd_other_unit, account_user: member)
    post_ticket(ticket_input.merge('unit_id' => sd_other_unit.id.to_s))
    expect(response).to have_http_status(:conflict)
    expect(tickets).to be_empty
  end

  it 'does not turn a mapping change into a duplicate in another unit with the same historical key' do
    post_ticket
    expect(response).to have_http_status(:created)
    create(:jrc_sd_membership, unit: sd_other_unit, account_user: member)
    business.update!(settings: business.settings.merge('service_desk_unit_id' => sd_other_unit.id.to_s))
    post_ticket(ticket_input.merge('unit_id' => sd_other_unit.id.to_s))
    expect(response).to have_http_status(:conflict)
    expect(tickets.count).to eq(1)
  end

  it 'rejects a requester override without treating it as authority to another contact' do
    altered = ticket_input.deep_dup
    altered.fetch('ticket')['requester_id'] = create(:contact, account: sd_foreign_account).id.to_s
    post_ticket(altered)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(tickets).to be_empty
  end

  it 'does not resolve or create a receipt from a recording belonging to another account' do
    foreign_record = record.dup
    foreign_record.account = sd_foreign_account
    foreign_record.save!
    post_ticket(ticket_input.merge('recording_id' => foreign_record.id.to_s))
    expect(response).to have_http_status(:not_found)
    expect(tickets).to be_empty
  end

  it 'denies an existing receipt after current recording authority is revoked while preserving the committed ticket' do
    post_ticket
    expect(response).to have_http_status(:created)
    original = tickets.sole.id
    remove_right!('jrc_contact_center_recordings_listen')
    post_ticket
    expect(response).to have_http_status(:forbidden)
    expect(tickets.pluck(:id)).to eq([original])
  end

  it 'does not infer a linked caller from a telephone match when the explicit contact is absent' do
    source_call.update!(contact_id: nil)
    post_ticket
    expect(response).to have_http_status(:forbidden)
    expect(tickets).to be_empty
  end

  it 'does not infer a destination when the business has no native Service Desk mapping' do
    business.update!(settings: business.settings.except('service_desk_unit_id'))
    post_ticket
    expect(response).to have_http_status(:unprocessable_entity)
    expect(tickets).to be_empty
  end

  it 'returns only the current authorized intake identifiers without creating a Ticket or reading the remote analysis' do
    get "/api/v1/accounts/#{account.id}/jrc_contact_center/recordings/#{record.id}/ticket_intake",
        headers: actor.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('contract_version' => 1, 'account_id' => account.id.to_s, 'user_id' => actor.id.to_s,
                                      'recording_id' => record.id.to_s, 'call_session_id' => source_call.id.to_s,
                                      'call_id' => source_call.external_session_id,
                                      'contact_id' => sd_contact.id.to_s, 'service_desk_unit_id' => sd_unit.id.to_s)
    expect(response.headers.fetch('Cache-Control')).to include('private', 'no-store')
    expect(provider).not_to have_received(:find_analysis)
    expect(tickets).to be_empty
  end

  it 'keeps the source correlation private through the existing native event projection after listening is revoked' do
    post_ticket
    expect(response).to have_http_status(:created)
    ticket = tickets.sole
    marker = ticket.ticket_events.find_by!(event_type: 'creation_context_recorded')
    expect(marker.data.fetch('recording_origin').fetch('call_id')).to eq(record.external_unique_id)
    remove_right!('jrc_contact_center_recordings_listen')
    expect(JrcServiceDesk::EventDataProjection.new(sd_context).call(marker)).to eq({})
    get "/api/v1/accounts/#{account.id}/jrc_service_desk/tickets/#{ticket.id}/events",
        headers: actor.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('recording_origin', 'recording_id', 'call_session_id', record.external_unique_id)
  end

  it 'does not accept a caller supplied recording-origin object or actor identity' do
    post_ticket(ticket_input.merge('recording_origin' => { 'recording_id' => record.id }, 'user_id' => actor.id))
    expect(response).to have_http_status(:unprocessable_entity)
    expect(tickets).to be_empty
  end
end
