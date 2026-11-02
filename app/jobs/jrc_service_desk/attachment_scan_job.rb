# frozen_string_literal: true

class JrcServiceDesk::AttachmentScanJob < ApplicationJob
  queue_as :low

  def perform(entry_id, force = false, attachment_id = nil)
    entry = JrcServiceDesk::IncidentEntry.find(entry_id)
    files = attachment_id ? entry.files.where(id: attachment_id) : entry.files
    files.each do |file|
      file.blob.with_lock do
        next if !force && JrcServiceDesk::AttachmentScanner.clean?(file.blob)
        next if !force && file.blob.metadata['service_desk_scan_state'] == 'infected'

        result = JrcServiceDesk::AttachmentScanner.new.scan(file.blob)
        file.blob.update!(metadata: file.blob.metadata.merge(result))
      end
    end
  end
end
