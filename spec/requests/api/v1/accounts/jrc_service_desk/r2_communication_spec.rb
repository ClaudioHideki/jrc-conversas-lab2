# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk R2 communication HTTP contracts', type: :request do
  include_context 'JRC Service Desk domain'
  let(:ticket) { sd_ticket }
  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/tickets/#{ticket.id}" }
  let(:headers) { sd_user.create_new_auth_token }

  def interaction(body = 'Authorized internal entry')
    JrcServiceDesk::AddNoteService.new(user_context: sd_context).call(ticket_id: ticket.id,
                                                                      attributes: { body: body }, idempotency_key: SecureRandom.uuid)
  end

  it 'returns authorized audience choices and prevents ordinary agents from selecting customer publication' do
    get "#{base}/composer_options", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('composer', 'audiences')).to eq(['internal'])
    post "#{base}/interaction_preview", params: { note: { body: 'Denied public response', visibility: 'customer' } }, headers: headers, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(ticket.ticket_notes).to be_empty
    sd_as_admin!
    get "#{base}/composer_options", headers: headers
    expect(response.parsed_body.dig('composer', 'audiences')).to include('customer', 'public_without_notification')
  end

  it 'rejects a public payload before its review' do
    sd_as_admin!
    values = { note: { body: 'Public silent publication', visibility: 'public_without_notification' } }
    post "#{base}/interactions", params: values, headers: headers.merge('Idempotency-Key' => 'r2-preview'), as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['code']).to eq('preview_invalid')
  end

  it 'performs a reviewed public payload write with independent immutable readback' do
    sd_as_admin!
    values = { note: { body: 'Public silent publication', visibility: 'public_without_notification' } }
    post "#{base}/interaction_preview", params: values, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    values[:preview_receipt] = response.parsed_body.dig('preview', 'receipt')
    post "#{base}/interactions", params: values, headers: headers.merge('Idempotency-Key' => 'r2-preview'), as: :json
    expect(response).to have_http_status(:created)
    identifier = response.parsed_body['result_id']
    get "#{base}/timeline", headers: headers
    expect(response).to have_http_status(:ok)
    row = response.parsed_body.dig('timeline', 'items').find { |item| item['kind'] == 'note' && item['id'] == identifier }
    expect(row.values_at('body', 'visibility', 'account_id', 'unit_id', 'ticket_id')).to eq(
      [values[:note][:body], values[:note][:visibility], sd_account.id.to_s, sd_unit.id.to_s, ticket.id.to_s]
    )
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(JrcServiceDesk::NotificationDelivery.where(ticket: ticket)).to be_empty
  end

  it 'paginates tied timestamps deterministically without duplicating interactions and their audit event' do
    instant = Time.current.change(usec: 123_456)
    notes = Array.new(3) { interaction }
    notes.each do |note|
      attributes = [ActiveRecord::Relation::QueryAttribute.new('created_at', instant, JrcServiceDesk::TicketNote.type_for_attribute('created_at')),
                    ActiveRecord::Relation::QueryAttribute.new('id', note.id, JrcServiceDesk::TicketNote.type_for_attribute('id'))]
      JrcServiceDesk::TicketNote.connection.exec_update(
        'UPDATE jrc_service_desk_ticket_notes SET created_at = $1 WHERE id = $2', 'Isolated tied-timestamp fixture', attributes
      )
    end
    get "#{base}/timeline", params: { per_page: 2 }, headers: headers
    expect(response).to have_http_status(:ok)
    first = response.parsed_body.fetch('timeline')
    expect(first['items'].map { |row| row['id'] }).to eq(notes.last(2).reverse.map { |note| note.id.to_s })
    expect(first['items'].map { |row| row['kind'] }).to eq(%w[note note])
    expect(first['next_cursor']).to be_present
    get "#{base}/timeline", params: { per_page: 2, cursor: first['next_cursor'] }, headers: headers
    expect(response).to have_http_status(:ok)
    second = response.parsed_body.fetch('timeline')
    expect(second['items'].map { |row| row['id'] }).to eq([notes.first.id.to_s])
    expect(second['next_cursor']).to be_nil
  end

  it 'rejects a cursor for another ticket or actor and never treats a cursor as a grant' do
    2.times { interaction }
    get "#{base}/timeline", params: { per_page: 1 }, headers: headers
    cursor = response.parsed_body.dig('timeline', 'next_cursor')
    other = sd_ticket
    get "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/tickets/#{other.id}/timeline", params: { cursor: cursor }, headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    sd_membership.update!(active: false)
    get "#{base}/timeline", params: { cursor: cursor }, headers: headers
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include('Authorized internal entry')
  end

  it 'omits technical source content after native team revocation across every timeline projection' do
    team = create(:team, account: sd_account)
    member = create(:team_member, team: team, user: sd_user)
    ticket.update!(team: team)
    JrcServiceDesk::AddNoteService.new(user_context: sd_context).call(
      ticket_id: ticket.id,
      attributes: { body: 'Sensitive technical timeline', visibility: 'technical_team', audience_team_id: team.id },
      idempotency_key: 'technical-r2'
    )
    get "#{base}/timeline", headers: headers
    expect(response.body).to include('Sensitive technical timeline')
    member.destroy!
    get "#{base}/timeline", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('Sensitive technical timeline')
  end

  it 'reuses native message sources from authorized links and does not copy messages from an unrelated conversation' do
    conversation = create(:conversation, account: sd_account, contact: sd_contact)
    create(:inbox_member, inbox: conversation.inbox, user: sd_user)
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
    message = create(:message, account: sd_account, inbox: conversation.inbox, conversation: conversation, content: 'Linked native source')
    foreign = create(:conversation, account: sd_account, contact: sd_contact)
    create(:message, account: sd_account, inbox: foreign.inbox, conversation: foreign, content: 'Unlinked native payload')
    get "#{base}/timeline", headers: headers
    expect(response).to have_http_status(:ok)
    rows = response.parsed_body.dig('timeline', 'items')
    expect(rows.count { |row| row['kind'] == 'message' && row['id'] == message.id.to_s }).to eq(1)
    expect(response.body).not_to include('Unlinked native payload')
  end

  it 'gates native files on both current source authorization and a verified scanner result without exposing storage URLs' do
    file = fixture_file_upload(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt'), 'text/plain')
    post "#{base}/interactions", params: { note: { body: 'Scanned timeline evidence' }, files: [file] },
                                 headers: headers.merge('Idempotency-Key' => 'r2-file')
    expect(response).to have_http_status(:created)
    note = ticket.ticket_notes.last
    attachment = note.files.first
    path = "#{base}/timeline/note/#{note.id}/attachments/#{attachment.id}"
    get path, headers: headers
    expect(response).to have_http_status(:conflict)
    attachment.blob.update!(metadata: { 'service_desk_scan_state' => 'clean' })
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    sd_membership.update!(active: false)
    get path, headers: headers
    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to include('rails/active_storage')
  end

  it 'removes notification audits and recipient metadata when native source access is revoked' do
    conversation = create(:conversation, account: sd_account, contact: sd_contact)
    source_grant = create(:inbox_member, inbox: conversation.inbox, user: sd_user)
    link = create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
    note = interaction('Authorized delivery origin')
    delivery = JrcServiceDesk::NotificationDelivery.create!(
      account: sd_account, unit: sd_unit, ticket: ticket,
      ticket_note: note, execution_membership: sd_membership, conversation: conversation, channel: 'email',
      state: 'blocked', recipient: 'current-source@example.test', reason: 'policy_disabled'
    )
    JrcServiceDesk::TicketEvent.create!(
      account: sd_account, unit: sd_unit, ticket: ticket, actor_membership: sd_membership,
      event_type: 'notification_delivery_updated', data: { 'delivery_id' => delivery.id, 'channel' => 'email', 'state' => 'blocked' }
    )
    get "#{base}/timeline", headers: headers
    expect(response.body).to include('current-source@example.test')
    source_grant.destroy!
    expect(link.reload).to be_readonly
    get "#{base}/timeline", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('current-source@example.test', 'notification_delivery_updated')
    get "#{base}/export", headers: headers
    expect(response).to have_http_status(:ok)
    audit = response.parsed_body.dig('cockpit', 'events').find { |row| row['event_type'] == 'notification_delivery_updated' }
    expect(audit['data']).to eq({})
    origin = response.parsed_body.dig('cockpit', 'notes').find { |row| row['id'] == note.id.to_s }
    expect(origin['deliveries']).to be_empty
  end

  it 'keeps Pundit policy caching distinct from the policy-list action across actual GET routes' do
    sd_as_admin!
    get "#{base}/composer_options", headers: headers
    expect(response).to have_http_status(:ok)
    get "#{base}/timeline", headers: headers
    expect(response).to have_http_status(:ok)
    path = "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/notification_policies"
    get path, params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.values_at('account_id', 'unit_id')).to eq([sd_account.id.to_s, sd_unit.id.to_s])
    expect(response.parsed_body['policies']).to eq([])
    sd_account_user.update!(role: 'agent')
    get path, params: { unit_id: sd_unit.id }, headers: headers
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).not_to have_key('policies')
  end
end
