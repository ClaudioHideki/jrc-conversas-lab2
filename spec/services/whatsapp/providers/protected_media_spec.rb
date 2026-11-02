# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Protected Service Desk WhatsApp media transport', type: :service do
  include_context 'JRC Service Desk domain'

  let(:channel) { create(:channel_whatsapp, account: sd_account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:conversation) { create(:conversation, account: sd_account, inbox: channel.inbox, contact: sd_contact) }
  let(:message) { create(:message, account: sd_account, inbox: channel.inbox, conversation: conversation, sender: sd_user, message_type: :outgoing) }
  let(:ticket) { sd_ticket }
  let(:attachment) do
    message.attachments.create!(account: sd_account, file_type: :file,
                                file: fixture_file_upload(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt'), 'text/plain'))
  end
  let(:service) { Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: channel) }
  let(:phone_path) { "https://graph.facebook.com/v24.0/#{channel.provider_config.fetch('phone_number_id')}" }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }
  let(:scan_proof) do
    { 'service_desk_scan_state' => 'clean', 'service_desk_scan_adapter' => 'clamav-instream-v1',
      'service_desk_scan_sha256' => Digest::SHA256.file(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt')).hexdigest,
      'service_desk_scanned_at' => Time.current.iso8601(6) }
  end

  before do
    create(:inbox_member, inbox: channel.inbox, user: sd_user)
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
    attachment.file.blob.update!(metadata: scan_proof)
  end

  it 'uploads protected bytes by multipart and sends the returned media id without a storage URL' do
    upload = stub_request(:post, "#{phone_path}/media").with do |request|
      request.headers['Content-Type'].start_with?('multipart/form-data') &&
        request.body.include?('name="messaging_product"') && request.body.include?('whatsapp') &&
        request.body.include?(File.read(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt')))
    end.to_return(status: 200, body: { id: 'synthetic-media-id' }.to_json, headers: json_headers)
    sent = stub_request(:post, "#{phone_path}/messages").with do |request|
      body = JSON.parse(request.body)
      body.dig('document', 'id') == 'synthetic-media-id' && !body.fetch('document').key?('link')
    end.to_return(status: 200, body: { messages: [{ id: 'synthetic-message-id' }] }.to_json, headers: json_headers)

    expect(service.send_message('+5511999999999', message)).to eq('synthetic-message-id')
    expect(upload).to have_been_requested.once
    expect(sent).to have_been_requested.once
  end

  it 'does not send the message or retry indefinitely when protected media upload fails' do
    stub_request(:post, "#{phone_path}/media").to_return(status: 500, body: '{}', headers: json_headers)

    expect(service.send_message('+5511999999999', message)).to be_nil
    expect(message.reload).to be_failed
    expect(message.external_error).to include('media upload failed')
    expect(a_request(:post, "#{phone_path}/messages")).not_to have_been_made
  end

  it 'rechecks native source rights before uploading any protected byte' do
    sd_membership.update!(active: false)

    expect(service.send_message('+5511999999999', message)).to be_nil
    expect(message.reload).to be_failed
    expect(a_request(:post, "#{phone_path}/media")).not_to have_been_made
    expect(a_request(:post, "#{phone_path}/messages")).not_to have_been_made
  end

  it 'fails a timed out protected upload without sending a message or enqueueing an automatic retry' do
    upload = stub_request(:post, "#{phone_path}/media").to_timeout

    expect do
      expect(service.send_message('+5511999999999', message)).to be_nil
    end.not_to have_enqueued_job(SendReplyJob)
    expect(message.reload).to be_failed
    expect(message.external_error).to include('media upload failed')
    expect(upload).to have_been_requested.once
    expect(a_request(:post, "#{phone_path}/messages")).not_to have_been_made
  end

  it 'keeps ordinary Cloud attachments on the existing link transport without media upload' do
    ordinary_conversation = create(:conversation, account: sd_account, inbox: channel.inbox)
    ordinary = create(:message, account: sd_account, inbox: channel.inbox, conversation: ordinary_conversation, message_type: :outgoing)
    ordinary.attachments.create!(account: sd_account, file_type: :file,
                                 file: fixture_file_upload(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt'), 'text/plain'))
    stub_request(:post, "#{phone_path}/messages").with do |request|
      JSON.parse(request.body).dig('document', 'link').present?
    end.to_return(status: 200, body: { messages: [{ id: 'ordinary-message-id' }] }.to_json, headers: json_headers)

    expect(service.send_message('+5511999999999', ordinary)).to eq('ordinary-message-id')
    expect(a_request(:post, "#{phone_path}/media")).not_to have_been_made
  end

  it 'fails protected legacy 360dialog media explicitly instead of disclosing a storage URL' do
    legacy = Whatsapp::Providers::Whatsapp360DialogService.new(whatsapp_channel: channel)

    expect(legacy.send_message('+5511999999999', message)).to be_nil
    expect(message.reload).to be_failed
    expect(message.external_error).to include('legacy 360dialog URL delivery is unavailable')
    expect(a_request(:post, 'https://waba.360dialog.io/v1/messages')).not_to have_been_made
  end
end
