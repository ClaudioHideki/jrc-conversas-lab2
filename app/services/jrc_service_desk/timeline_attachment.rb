# frozen_string_literal: true

class JrcServiceDesk::TimelineAttachment
  def initialize(ticket:, context:)
    @sources = JrcServiceDesk::TimelineSources.new(ticket: ticket, context: context).call
  end

  def call(kind:, record_id:, attachment_id:)
    raise ArgumentError unless %w[note message call].include?(kind)

    record = @sources.fetch(kind).find(JrcServiceDesk::Input.id(record_id))
    identifier = JrcServiceDesk::Input.id(attachment_id)
    file = file_for(kind, record, identifier)
    raise JrcServiceDesk::AttachmentScanError unless file.blob.metadata['service_desk_scan_state'] == 'clean'

    file
  end

  private

  def file_for(kind, record, identifier)
    return record.files.find(identifier) if kind == 'note'
    return record.attachments.find(identifier).file if kind == 'message'
    return record.recording if record.recording.attached? && record.recording.id == identifier

    raise ActiveRecord::RecordNotFound
  end
end
