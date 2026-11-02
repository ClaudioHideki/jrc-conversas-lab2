# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Protected Service Desk attachments at native delivery boundaries', type: :service do
  include_context 'JRC Service Desk domain'

  let(:inbox) { create(:inbox, account: sd_account) }
  let(:conversation) { create(:conversation, account: sd_account, inbox: inbox, contact: sd_contact) }
  let(:ticket) { sd_ticket }
  let(:message) { create(:message, account: sd_account, inbox: inbox, conversation: conversation, sender: sd_user, message_type: :outgoing) }
  let(:attachment) do
    message.attachments.create!(account: sd_account, file_type: :file,
                                file: fixture_file_upload(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt'), 'text/plain'))
  end
  let(:scan_proof) do
    { 'service_desk_scan_state' => 'clean', 'service_desk_scan_adapter' => 'clamav-instream-v1',
      'service_desk_scan_sha256' => Digest::SHA256.file(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt')).hexdigest,
      'service_desk_scanned_at' => Time.current.iso8601(6) }
  end

  before do
    create(:inbox_member, inbox: inbox, user: sd_user)
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
    attachment.file.blob.update!(metadata: scan_proof)
  end

  it 'does not call the provider after the recorded native author loses source rights, even with another Current user' do
    sd_as_admin!
    source_ticket = create(:jrc_sd_ticket, unit: sd_other_unit)
    source_note = create(:jrc_sd_note, ticket: source_ticket,
                                       files: [fixture_file_upload(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt'), 'text/plain')])
    source_blob = source_note.files.first.blob
    source_blob.update!(metadata: scan_proof)
    queued = Messages::MessageBuilder.new(sd_user, conversation, ActionController::Parameters.new(
      content: 'Synthetic authorized queued copy', message_type: 'outgoing', private: false, attachments: [source_blob.signed_id]
    )).perform
    sd_account_user.update!(role: :agent)
    incidental_admin = create(:account_user, account: sd_account, role: :administrator)
    Current.user = incidental_admin.user
    Current.account_user = incidental_admin
    expect(Messages::SendEmailNotificationService).not_to receive(:new)

    SendReplyJob.new.deliver(queued)

    expect(queued.reload).to be_failed
    expect(queued.external_error).to include('attachment access revoked')
  ensure
    Current.reset
  end

  it 'still invokes the native service for an authorized own public protected attachment' do
    delivery = instance_double(Messages::SendEmailNotificationService, perform: nil)
    expect(Messages::SendEmailNotificationService).to receive(:new).with(message: message).and_return(delivery)

    SendReplyJob.new.deliver(message)
  end

  it 'never mints a direct storage bearer URL for a protected blob' do
    expect(attachment.file.blob).not_to receive(:url)

    expect { attachment.download_url }.to raise_error(Pundit::NotAuthorizedError, /signed storage URL delivery is unavailable/)
  end

  it 'fails protected API inbox media without sending a bearer URL' do
    api_channel = create(:channel_api, account: sd_account)
    api_inbox = api_channel.inbox
    create(:inbox_member, inbox: api_inbox, user: sd_user)
    api_conversation = create(:conversation, account: sd_account, inbox: api_inbox, contact: sd_contact)
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: api_conversation)
    api_message = create(:message, account: sd_account, inbox: api_inbox, conversation: api_conversation,
                                   sender: sd_user, message_type: :outgoing)
    api_message.attachments.create!(account: sd_account, file_type: :file, file: attachment.file.blob)
    expect(SafeFetch).not_to receive(:fetch)

    Webhooks::Trigger.execute('https://broker.example.test/webhook', { id: api_message.id, event: 'message_created' }, :api_inbox_webhook)

    expect(api_message.reload).to be_failed
    expect(api_message.external_error).to include('API inbox URL delivery is unavailable')
  end

  it 'preserves native API inbox text webhooks without introducing a media contract' do
    api_channel = create(:channel_api, account: sd_account)
    api_conversation = create(:conversation, account: sd_account, inbox: api_channel.inbox, contact: sd_contact)
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: api_conversation)
    text_message = create(:message, account: sd_account, inbox: api_channel.inbox, conversation: api_conversation,
                                    sender: sd_user, message_type: :outgoing, content: 'Synthetic public text')
    url = 'https://broker.example.test/webhook'
    expect(SafeFetch).to receive(:fetch).with(url, hash_including(method: :post)).and_yield(instance_double(SafeFetch::Result))

    Webhooks::Trigger.execute(url, { id: text_message.id, event: 'message_created' }, :api_inbox_webhook)

    expect(text_message.reload).not_to be_failed
  end
end
