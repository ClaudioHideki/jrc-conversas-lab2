require 'base64'

class JrcMigrations::AttachmentPayload
  MAX_BYTES = 1.megabyte
  attr_reader :bytes, :sha256, :filename, :content_type

  def initialize(data)
    @bytes = Base64.strict_decode64(data.fetch('file_base64')).freeze
    @sha256 = Digest::SHA256.hexdigest(bytes)
    @filename = data['filename']
    @content_type = data['content_type']
    validate!(data)
  rescue ArgumentError, KeyError, TypeError
    raise JrcMigrations::Error, 'INVALID_ATTACHMENT_INPUT'
  end

  def metadata(account_id:, source:)
    { 'migration_sha256' => sha256, 'migration_account_id' => account_id, 'migration_source' => source,
      'service_desk_scan_state' => 'unavailable' }
  end

  private

  def validate!(data)
    raise JrcMigrations::Error, 'ATTACHMENT_HASH_MISMATCH' unless data['file_sha256'] == sha256
    raise JrcMigrations::Error, 'ATTACHMENT_SIZE_MISMATCH' unless valid_size?(data['file_size'])
    raise JrcMigrations::Error, 'INVALID_ATTACHMENT_INPUT' unless valid_filename? && valid_type?

    validate_signature!
  end

  def valid_size?(value)
    value.to_s == bytes.bytesize.to_s && bytes.bytesize.between?(1, MAX_BYTES)
  end

  def valid_filename?
    filename.is_a?(String) && filename.present? && filename.length <= 255 && !filename.match?(%r{[\x00/\\]})
  end

  def valid_type?
    content_type.is_a?(String) && content_type.bytesize <= 255 && %r{\A[\w.+-]+/[\w.+-]+\z}.match?(content_type)
  end

  def validate_signature!
    signature = { 'application/pdf' => '%PDF-'.b, 'image/png' => "\x89PNG\r\n\x1a\n".b, 'image/jpeg' => "\xff\xd8\xff".b }[content_type]
    raise JrcMigrations::Error, 'ATTACHMENT_TYPE_MISMATCH' if signature && !bytes.start_with?(signature)
  end
end
