# frozen_string_literal: true

require 'rails_helper'
require 'socket'

RSpec.describe 'Service Desk case attachment security', type: :request do
  include_context 'JRC Service Desk domain'
  let(:base) { "/api/v1/accounts/#{sd_account.id}/jrc_service_desk/case_workspaces" }
  let(:headers) { sd_user.create_new_auth_token }
  let(:record) do
    JrcServiceDesk::CreateIncidentService.new(user_context: sd_context).call(unit_id: sd_unit.id,
                                                                             attributes: { resource_kind: 'incident', title: 'Synthetic attachment case', severity: 'normal' }, idempotency_key: SecureRandom.uuid)
  end
  let(:upload) do
    tempfile = Tempfile.new(['jrc-sd-synthetic', '.txt'])
    tempfile.write('Synthetic safe test content')
    tempfile.rewind
    ActionDispatch::Http::UploadedFile.new(tempfile: tempfile, type: 'text/plain', filename: 'synthetic.txt')
  end
  let(:entry) do
    outcome = JrcServiceDesk::CaseCommandService.new(user_context: sd_context).call(unit_id: sd_unit.id, incident_id: record.id,
                                                                                    action: 'attach', attributes: { body: 'Synthetic supporting evidence' }, expected_lock_version: record.lock_version, idempotency_key: 'synthetic-upload', files: [upload])
    outcome[:entry]
  end
  let(:file) { entry.files.first! }

  before { sd_as_admin! }

  # Exercise the actual local INSTREAM protocol adapter and ActiveStorage bytes.
  # Only the antivirus daemon is simulated. No metadata is manually marked clean.
  def scan_with(reply)
    path = "/tmp/jrc-sd-clam-#{SecureRandom.hex(5)}.sock"
    received = +''
    server = UNIXServer.new(path)
    worker = Thread.new do
      client = server.accept
      raise 'Bad scanner command' unless client.read(10) == "zINSTREAM\0"

      loop do
        length = client.read(4).unpack1('N')
        break if length.zero?

        received << client.read(length)
      end
      client.write(reply)
      client.close
    end
    # /run is read-only in the isolated container. Map only this mocked daemon
    # endpoint to the test-owned Unix server; exercise real framed bytes below.
    allow(UNIXSocket).to receive(:open).with('/run/jrc-sd-test-clam.sock') do |&block|
      client = UNIXSocket.new(path)
      begin
        block.call(client)
      ensure
        client.close
      end
    end
    with_modified_env JRC_SD_CLAMAV_SOCKET: '/run/jrc-sd-test-clam.sock' do
      JrcServiceDesk::AttachmentScanJob.perform_now(entry.id, true)
    end
    worker.value
    expect(received).to eq('Synthetic safe test content')
  ensure
    server&.close
    File.unlink(path) if path && File.exist?(path)
    worker&.kill if worker&.alive?
  end

  def download
    get "#{base}/#{record.id}/entries/#{entry.id}/attachments/#{file.id}", headers: headers
  end
  it 'blocks unverified files; releases only bytes verified through the configured scanner' do
    download
    expect(response).to have_http_status(:conflict)
    scan_with("stream: OK\0")
    expect(file.blob.reload.metadata['service_desk_scan_state']).to eq('clean')
    download
    expect(response).to have_http_status(:ok), response.body
    expect(response.body).to eq('Synthetic safe test content')
  end

  it 'blocks an infected verdict and a malformed scanner response' do
    scan_with("stream: Synthetic-Test-Signature FOUND\0")
    download
    expect(response).to have_http_status(:conflict)
    scan_with("invalid daemon response\0")
    expect(file.blob.reload.metadata['service_desk_scan_state']).to eq('unavailable')
    download
    expect(response).to have_http_status(:conflict)
  end

  it 'rejects a real Widget Case signed_id reattachment and preserves the official Case endpoint' do
    scan_with("stream: OK\0")
    blob = file.blob.reload
    widget = create(:channel_widget, account: sd_account)
    identity = create(:contact_inbox, contact: sd_contact, inbox: widget.inbox, hmac_verified: false)
    conversation = create(:conversation, account: sd_account, contact: sd_contact, inbox: widget.inbox, contact_inbox: identity)
    ticket = sd_ticket
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
    widget_headers = { 'X-Auth-Token' => Widget::TokenService.new(payload: { source_id: identity.source_id, inbox_id: widget.inbox.id }).generate_token }
    blob_path = Rails.application.routes.url_helpers.rails_blob_path(file, only_path: true)

    get blob_path
    expect(response).to have_http_status(:not_found)
    get blob_path, headers: headers
    expect(response).to have_http_status(:not_found)

    expect do
      post '/api/v1/widget/messages', headers: widget_headers,
                                     params: { website_token: widget.website_token, message: { content: 'Synthetic Case reattachment', attachments: [blob.signed_id] } }
    end.not_to change(conversation.messages, :count)
    expect(response).to have_http_status(:unprocessable_entity), response.body

    download
    expect(response).to have_http_status(:ok), response.body
    expect(response.body).to eq('Synthetic safe test content')
  end

  it 'blocks when the scanner is unconfigured and never treats a clean label alone as a scan proof' do
    file.blob.update!(metadata: { 'service_desk_scan_state' => 'clean' })
    download
    expect(response).to have_http_status(:conflict)
    with_modified_env JRC_SD_CLAMAV_SOCKET: nil do
      JrcServiceDesk::AttachmentScanJob.perform_now(entry.id, true)
    end
    expect(file.blob.reload.metadata['service_desk_scan_state']).to eq('unavailable')
  end

  it 'audits withdrawal, retains the stored evidence, and rejects subsequent download or recheck' do
    scan_with("stream: OK\0")
    post "#{base}/#{record.id}/commands", headers: headers.merge('Idempotency-Key' => 'withdraw-once'), as: :json,
                                          params: { action: 'withdraw_attachment', attributes: { entry_id: entry.id, attachment_id: file.id, reason: 'Synthetic authorized withdrawal' }, expected_lock_version: record.reload.lock_version }
    expect(response).to have_http_status(:ok), response.body
    download
    expect(response).to have_http_status(:not_found)
    expect(file.blob.reload).to be_persisted
    expect(record.incident_entries.where(event_type: 'attachment_withdrawn').count).to eq(1)
  end

  it 'does not expose the attachment through another Account' do
    file
    outsider = create(:user, account: sd_foreign_account, role: :administrator)
    get "#{base}/#{record.id}/entries/#{entry.id}/attachments/#{file.id}", headers: outsider.create_new_auth_token
    expect(response).to have_http_status(:forbidden)
  end

  it 'accepts a real multipart HTTP upload once and persists a reasoned security recheck command' do
    source = Tempfile.new(['jrc-http-upload', '.txt'])
    source.write('Synthetic HTTP upload')
    source.rewind
    request_file = Rack::Test::UploadedFile.new(source.path, 'text/plain')
    count = record.incident_entries.count
    post "#{base}/#{record.id}/commands", headers: headers.merge('Idempotency-Key' => 'multipart-once'),
                                          params: { action: 'attach', attributes: { body: 'Synthetic multipart attachment' }.to_json, expected_lock_version: record.lock_version, files: [request_file] }
    expect(response).to have_http_status(:ok), response.body
    uploaded = record.incident_entries.find_by!(event_type: 'attachment_added')
    expect(uploaded.files.first!.blob.download).to eq('Synthetic HTTP upload')
    expect(record.incident_entries.count).to eq(count + 1)
    post "#{base}/#{record.id}/commands", headers: headers.merge('Idempotency-Key' => 'rescan-once'), as: :json,
                                          params: { action: 'rescan_attachment', attributes: { entry_id: uploaded.id, attachment_id: uploaded.files.first!.id }, expected_lock_version: record.reload.lock_version }
    expect(response).to have_http_status(:ok), response.body
    expect(record.incident_entries.where(event_type: 'updated').last.data['attachment_rescan_entry_id']).to eq(uploaded.id)
  ensure
    source&.close!
  end
end
