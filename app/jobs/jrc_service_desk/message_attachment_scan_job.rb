# frozen_string_literal: true

# Native Widget uploads use Message/Attachment, rather than IncidentEntry.files.
class JrcServiceDesk::MessageAttachmentScanJob < ApplicationJob
  queue_as :low

  def perform(attachment_id)
    attachment = ::Attachment.find_by(id: attachment_id)
    return unless attachment&.service_desk_protected?

    blob = attachment.file.blob
    blob.with_lock do
      next if JrcServiceDesk::AttachmentScanner.clean?(blob) || blob.metadata['service_desk_scan_state'] == 'infected'

      result = JrcServiceDesk::AttachmentScanner.new.scan(blob)
      blob.update!(metadata: blob.metadata.merge(result))
    end
  end
end
