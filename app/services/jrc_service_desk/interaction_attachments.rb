# frozen_string_literal: true

require 'digest'

module JrcServiceDesk::InteractionAttachments
  def self.prepare(files)
    raise ArgumentError, 'At most five uploaded attachments are supported' unless files.is_a?(Array) && files.size <= 5

    files.map do |file|
      raise ArgumentError, 'A real uploaded file is required' unless file.is_a?(ActionDispatch::Http::UploadedFile)
      raise ArgumentError, 'Attachment exceeds the supported size' unless file.size.positive? && file.size <= 20.megabytes

      digest = Digest::SHA256.file(file.tempfile.path).hexdigest
      file.tempfile.rewind
      { io: file.tempfile, filename: File.basename(file.original_filename.to_s), content_type: file.content_type,
        sha256: digest, metadata: { service_desk_scan_state: 'unavailable' } }
    end
  end
end
