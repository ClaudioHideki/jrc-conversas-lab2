# frozen_string_literal: true

class JrcServiceDesk::AttachmentScanError < StandardError
  def initialize
    super('Attachment awaits a verified malware scan')
  end
end
