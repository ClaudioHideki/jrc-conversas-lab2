# frozen_string_literal: true

require 'digest'

# Header inspection is admission to private quarantine, never evidence of a clean or playable file.
class JrcContactCenter::AudioFileInput
  TYPES = { 'audio/mpeg' => 'audio/mpeg', 'audio/wav' => 'audio/wav', 'audio/x-wav' => 'audio/wav',
            'audio/vnd.wave' => 'audio/wav', 'audio/ogg' => 'audio/ogg', 'audio/mp4' => 'audio/mp4' }.freeze
  attr_reader :file, :filename, :content_type, :byte_size, :sha256

  def self.max_bytes
    limit = GlobalConfigService.load('MAXIMUM_FILE_UPLOAD_SIZE', 40).to_i
    (limit.positive? ? limit : 40).megabytes
  end

  def initialize(file:)
    raise JrcContactCenter::OperationError, 'invalid_institutional_audio_file' unless file.is_a?(ActionDispatch::Http::UploadedFile)

    @file = file
    @filename = ActiveStorage::Filename.new(file.original_filename).to_s
    @byte_size = file.size
    validate_admission!
    @content_type = TYPES[Marcel::MimeType.for(file.tempfile)]
    raise JrcContactCenter::OperationError, 'unsupported_institutional_audio_file' unless @content_type

    @sha256 = Digest::SHA256.file(file.tempfile.path).hexdigest
  end

  def version_attributes
    { file_name: @filename, content_type: @content_type, byte_size: @byte_size, sha256: @sha256 }
  end

  def verify_stored!(blob)
    raise ActiveStorage::IntegrityError unless blob.byte_size == @byte_size

    blob.open do |stored|
      valid = stored.size == @byte_size && Digest::SHA256.file(stored.path).hexdigest == @sha256
      raise ActiveStorage::IntegrityError unless valid
    end
  end

  private

  def validate_admission!
    valid = @filename.present? && @filename.length <= 255 && @byte_size.positive? && @byte_size <= self.class.max_bytes
    raise JrcContactCenter::OperationError, 'invalid_institutional_audio_file' unless valid
  end
end
