# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'R3 catalogue and real opening attachments', type: :request do
  include_context 'JRC Service Desk domain'
  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk" }
  let(:headers) { sd_user.create_new_auth_token.merge('Idempotency-Key' => 'r3-opening-upload') }
  let(:type) { JrcServiceDesk::TicketType.create!(account: sd_account, unit: sd_unit, name: 'Request', code: 'request', active: true) }
  let(:file) { Rack::Test::UploadedFile.new(Rails.root.join('spec/assets/sample.png'), 'image/png') }

  before { sd_as_admin! }

  it 'persists uploaded bytes in one internal native note without sending a message' do
    values = { unit_id: sd_unit.id, ticket: sd_create_attributes.to_json, files: [file] }
    post "#{base}/tickets", params: values, headers: headers
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch('ticket_id')
    ticket = JrcServiceDesk::Ticket.find(id)
    note = ticket.ticket_notes.sole
    expect(note.visibility).to eq('internal')
    expect(Digest::SHA256.hexdigest(note.files.sole.download)).to eq(Digest::SHA256.file(Rails.root.join('spec/assets/sample.png')).hexdigest)
    expect(JrcServiceDesk::NotificationDelivery.count).to eq(0)
    expect(Message.count).to eq(0)
  end

  it 'safely replays with the same ticket and note and reads back one attachment with the original byte size' do
    post "#{base}/tickets", params: { unit_id: sd_unit.id, ticket: sd_create_attributes.to_json, files: [file] }, headers: headers
    id = response.parsed_body.fetch('ticket_id')
    note_id = response.parsed_body.fetch('opening_note_id')
    ticket = JrcServiceDesk::Ticket.find(id)
    note = ticket.ticket_notes.sole
    post "#{base}/tickets", params: { unit_id: sd_unit.id, ticket: sd_create_attributes.to_json, files: [file] }, headers: headers
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.fetch('ticket_id')).to eq(id)
    expect(response.parsed_body.fetch('opening_note_id')).to eq(note_id)
    get "#{base}/tickets/#{id}/notes/#{note_id}", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('item', 'attachments', 0, 'byte_size')).to eq(File.size(Rails.root.join('spec/assets/sample.png')))
    expect(ticket.reload.ticket_notes.count).to eq(1)
    expect(note.reload.files.count).to eq(1)
  end

  it 'rejects a different attachment envelope and leaves the original ticket and bytes intact' do
    post "#{base}/tickets", params: { unit_id: sd_unit.id, ticket: sd_create_attributes.to_json, files: [file] }, headers: headers
    expect(response).to have_http_status(:created)
    post "#{base}/tickets", params: { unit_id: sd_unit.id, ticket: sd_create_attributes.to_json }, headers: headers
    expect(response).to have_http_status(:conflict)
    expect(JrcServiceDesk::Ticket.where(account: sd_account).count).to eq(1)
    expect(JrcServiceDesk::TicketNote.where(account: sd_account).sole.files.count).to eq(1)
  end

  it 'returns the explicit catalogue selection then denies it after membership revocation' do
    get "#{base}/catalogue_form", params: { unit_id: sd_unit.id, ticket_type_id: type.id }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('ticket_type', 'id')).to eq(type.id.to_s)
    sd_membership.update!(active: false)
    get "#{base}/catalogue_form", params: { unit_id: sd_unit.id, ticket_type_id: type.id }, headers: headers
    expect(response).to have_http_status(:not_found)
  end
end
