# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Service Desk V2 cockpit HTTP policy projections', type: :request do
  include_context 'JRC Service Desk domain'
  let(:ticket) { sd_ticket }
  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/tickets/#{ticket.id}" }
  let(:headers) { sd_user.create_new_auth_token }

  it 'persists a public silent interaction with readback while an ordinary agent is denied publication' do
    values = { note: { body: 'Customer visible update', visibility: 'public_without_notification' } }
    post "#{base}/interactions", params: values, headers: headers.merge('Idempotency-Key' => 'public-note'), as: :json
    expect(response).to have_http_status(:forbidden)
    sd_as_admin!
    post "#{base}/interaction_preview", params: values, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    values[:preview_receipt] = response.parsed_body.dig('preview', 'receipt')
    post "#{base}/interactions", params: values, headers: headers.merge('Idempotency-Key' => 'public-note'), as: :json
    expect(response).to have_http_status(:created)
    note_id = response.parsed_body['result_id']
    get "#{base}/cockpit", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('cockpit', 'notes').first.values_at('id', 'body',
                                                                        'visibility')).to eq([note_id, 'Customer visible update',
                                                                                              'public_without_notification'])
    expect(response.headers['Cache-Control']).to include('no-store')
    expect(JrcServiceDesk::NotificationDelivery.count).to eq(0)
  end

  it 'removes technical content before cockpit, export, collections and individual item serialization after team revocation' do
    team = create(:team, account: sd_account)
    member = create(:team_member, team: team, user: sd_user)
    ticket.update!(team: team)
    note = JrcServiceDesk::AddNoteService.new(user_context: sd_context).call(
      ticket_id: ticket.id,
      attributes: { body: 'Protected technical payload', visibility: 'technical_team', audience_team_id: team.id },
      idempotency_key: 'technical-http'
    )
    member.destroy!
    %w[cockpit export notes events].each do |endpoint|
      get "#{base}/#{endpoint}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('Protected technical payload', 'technical-http')
    end
    get "#{base}/notes/#{note.id}", headers: headers
    expect(response).to have_http_status(:forbidden)
  end

  it 'does not expose an inaccessible ticket in another unit to cockpit or export' do
    other_member = create(:account_user, account: sd_account, role: :agent)
    row = sd_ticket(unit: sd_other_unit, status: create(:jrc_sd_status, unit: sd_other_unit), priority: create(:jrc_sd_priority, unit: sd_other_unit),
                    created_by_membership: create(:jrc_sd_membership, unit: sd_other_unit, account_user: other_member))
    %w[cockpit export].each do |endpoint|
      get "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/tickets/#{row.id}/#{endpoint}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  it 'uploads only to an authorized immutable interaction and gates downloads on a verified scan' do
    file = fixture_file_upload(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt'), 'text/plain')
    post "#{base}/interactions", params: { note: { body: 'Evidence attachment' }, files: [file] },
                                 headers: headers.merge('Idempotency-Key' => 'attachment-http')
    expect(response).to have_http_status(:created)
    note = ticket.ticket_notes.last
    attachment = note.files.first
    path = "#{base}/notes/#{note.id}/attachments/#{attachment.id}"
    get path, headers: headers
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['code']).to eq('attachment_scan_unavailable')
    immutable_attributes = note.attributes
    # Simulated scanner result in test DB only.
    attachment.blob.update!(metadata: attachment.blob.metadata.merge('service_desk_scan_state' => 'clean'))
    expect(note.reload.attributes).to eq(immutable_attributes)
    get path, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.headers['Content-Disposition']).to include('attachment')
    sd_membership.update!(active: false)
    get path, headers: headers
    expect(response).to have_http_status(:forbidden)
  end

  it 'rejects changing the body or visibility of the native uploaded interaction' do
    file = fixture_file_upload(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt'), 'text/plain')
    post "#{base}/interactions", params: { note: { body: 'Evidence attachment' }, files: [file] },
                                 headers: headers.merge('Idempotency-Key' => 'attachment-http')
    expect(response).to have_http_status(:created)
    note = ticket.ticket_notes.last
    expect { note.update!(body: 'Edited scanned evidence') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { note.update!(visibility: 'public_without_notification') }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
