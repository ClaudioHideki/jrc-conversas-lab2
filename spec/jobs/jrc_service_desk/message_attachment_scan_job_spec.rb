# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JrcServiceDesk::MessageAttachmentScanJob, type: :job do
  include_context 'JRC Service Desk domain'

  let(:widget) { create(:channel_widget, account: sd_account) }
  let(:identity) { create(:contact_inbox, contact: sd_contact, inbox: widget.inbox) }
  let(:conversation) { create(:conversation, account: sd_account, contact: sd_contact, inbox: widget.inbox, contact_inbox: identity) }
  let(:ticket) { sd_ticket }
  let(:message) { create(:message, account: sd_account, inbox: widget.inbox, conversation: conversation, sender: sd_contact) }
  let(:file) do
    upload = fixture_file_upload(Rails.root.join('spec/fixtures/files/jrc_projects_task.txt'), 'text/plain')
    ActionDispatch::Http::UploadedFile.new(tempfile: upload.tempfile, filename: upload.original_filename, type: upload.content_type)
  end
  let(:attachment) { message.attachments.create!(account: sd_account, file_type: :file, file: file) }

  it 'queues a newly committed native attachment only after its same-Account SD link is visible' do
    # Complete the native channel/Inbox factory callbacks before opening the
    # transaction whose Attachment + Service Desk link commit is under test.
    owner_message = message
    owner_conversation = owner_message.conversation
    owner_ticket = ticket
    created = nil
    expect do
      ApplicationRecord.transaction do
        created = owner_message.attachments.create!(account: sd_account, file_type: :file, file: file)
        create(:jrc_sd_conversation_link, ticket: owner_ticket, conversation: owner_conversation)
      end
    end.to have_enqueued_job(described_class).with { |attachment_id| expect(attachment_id).to eq(created.id) }.on_queue('low')
    expect(created.file.blob.reload.metadata['service_desk_scan_state']).to eq('unavailable')
  end

  it 'does not queue an ordinary attachment or scan unrelated legacy blobs' do
    expect { attachment }.not_to have_enqueued_job(described_class)
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
    expect { attachment.reload.push_event_data }.not_to have_enqueued_job(described_class)
    expect(attachment.file.blob.metadata['service_desk_scan_state']).to be_nil
  end

  %w[aborted raised].each do |failure|
    it "allows a later callback to retry an #{failure} enqueue without duplicating the successful scan" do
      saved = attachment
      create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
      attempts = 0
      allow(described_class).to receive(:perform_later).and_wrap_original do |original, *arguments|
        attempts += 1
        if attempts == 1
          raise ActiveJob::EnqueueError, 'Synthetic queue failure' if failure == 'raised'

          false
        else
          original.call(*arguments)
        end
      end

      if failure == 'raised'
        expect { saved.send(:enqueue_service_desk_scan) }.to raise_error(ActiveJob::EnqueueError, 'Synthetic queue failure')
      else
        saved.send(:enqueue_service_desk_scan)
      end
      expect do
        saved.send(:enqueue_service_desk_scan)
        saved.send(:enqueue_service_desk_scan)
      end.to have_enqueued_job(described_class).with(saved.id).exactly(:once)
      expect(described_class).to have_received(:perform_later).with(saved.id).twice
      expect(saved.file.blob.reload.metadata['service_desk_scan_state']).to eq('unavailable')
    end
  end

  it 'queues a real PortalCustomerMessage upload after its native Attachment file has been saved' do
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
    created = nil
    expect do
      created = JrcServiceDesk::PortalCustomerMessage.create!(
        conversation: conversation, contact: sd_contact, content: 'Synthetic public upload', source_id: 'widget-scan-test',
        content_attributes: { 'service_desk_ticket_id' => ticket.id.to_s }, files: [file]
      )
    end.to have_enqueued_job(described_class).with(kind_of(Integer)).on_queue('low')
    expect(created.attachments.first.file).to be_attached
    expect(created.attachments.first.file.blob.reload.metadata['service_desk_scan_state']).to eq('unavailable')
  end

  %w[clean infected unavailable].each do |state|
    it "persists the official scanner's #{state} result for exactly the queued new attachment" do
      create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
      result = { 'service_desk_scan_state' => state }
      scanner = instance_double(JrcServiceDesk::AttachmentScanner, scan: result)
      allow(JrcServiceDesk::AttachmentScanner).to receive(:new).and_return(scanner)

      described_class.perform_now(attachment.id)

      expect(scanner).to have_received(:scan).with(attachment.file.blob)
      expect(attachment.file.blob.reload.metadata['service_desk_scan_state']).to eq(state)
    end
  end

  it 'remains unavailable when the optional ClamAV socket has not been configured' do
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
    with_modified_env JRC_SD_CLAMAV_SOCKET: nil do
      described_class.perform_now(attachment.id)
    end
    expect(attachment.file.blob.reload.metadata['service_desk_scan_state']).to eq('unavailable')
  end

  it 'does not turn an infected blob clean when it is reattached or the job is retried' do
    create(:jrc_sd_conversation_link, ticket: ticket, conversation: conversation)
    blob = attachment.file.blob
    blob.update!(metadata: { 'service_desk_scan_state' => 'infected' })
    allow(JrcServiceDesk::AttachmentScanner).to receive(:new)
    expect do
      message.attachments.create!(account: sd_account, file_type: :file, file: blob)
    end.not_to have_enqueued_job(described_class)
    described_class.perform_now(attachment.id)
    expect(JrcServiceDesk::AttachmentScanner).not_to have_received(:new)
    expect(blob.reload.metadata['service_desk_scan_state']).to eq('infected')
  end

  it 'does not scan a disappeared attachment or an attachment outside a linked SD conversation' do
    allow(JrcServiceDesk::AttachmentScanner).to receive(:new)
    described_class.perform_now(0)
    described_class.perform_now(attachment.id)
    expect(JrcServiceDesk::AttachmentScanner).not_to have_received(:new)
  end
end
