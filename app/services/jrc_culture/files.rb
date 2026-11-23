# frozen_string_literal: true

require 'zip'

class JrcCulture::Files
  class Invalid < StandardError; end

  MARKER = 'jrc_culture_private'
  TYPES = {
    'pdf' => 'application/pdf',
    'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  }.freeze

  def self.upload!(file, kind:)
    raise Invalid unless file.respond_to?(:tempfile) && file.size.between?(5, 15.megabytes)

    io = file.tempfile
    validate_type!(io, kind)
    blob = ActiveStorage::Blob.create_after_unfurling!(
      io: io, filename: "manual-de-cultura.#{kind}", content_type: TYPES.fetch(kind),
      identify: false, metadata: { MARKER => true }
    )
    raise Invalid if blob.service.public?

    blob.upload_without_unfurling(io)
    result = JrcServiceDesk::AttachmentScanner.new.scan(blob)
    blob.update!(metadata: blob.metadata.merge(result))
    raise Invalid unless JrcServiceDesk::AttachmentScanner.clean?(blob)

    blob
  rescue StandardError
    discard_unowned(blob)
    raise
  end

  def self.download(blob)
    raise Invalid unless blob.metadata[MARKER] == true && !blob.service.public?

    JrcServiceDesk::AttachmentScanner.download(blob)
  rescue JrcServiceDesk::AttachmentScanError
    raise Invalid
  end

  def self.discard_unowned(blob)
    return unless blob&.persisted? && blob.metadata[MARKER] == true
    return if JrcCulture::Asset.exists?(blob_id: blob.id) || JrcCulture::Import.exists?(blob_id: blob.id)

    blob.purge
  rescue StandardError => e
    Rails.logger.warn("jrc_culture_blob_cleanup_pending class=#{e.class.name}")
  end

  def self.validate_type!(io, kind)
    io.rewind
    case kind
    when 'pdf'
      raise Invalid unless io.read(5) == '%PDF-'
    when 'xlsx', 'pptx'
      main = kind == 'xlsx' ? 'xl/workbook.xml' : 'ppt/presentation.xml'
      Zip::File.open(io.path) do |archive|
        raise Invalid unless archive.find_entry('[Content_Types].xml') && archive.find_entry(main)
        raise Invalid if archive.any? { |entry| entry.name.downcase.end_with?('vbaproject.bin') }
      end
    else
      raise Invalid
    end
  rescue Zip::Error
    raise Invalid
  ensure
    io.rewind
  end
  private_class_method :validate_type!
end
