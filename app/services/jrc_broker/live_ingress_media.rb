require 'digest'
require 'stringio'

class JrcBroker::LiveIngressMedia
  def verify_bytes!(bytes, descriptor)
    mime = JrcBroker::MediaMime.detect(bytes, filename: descriptor.fetch('filename'), declared: descriptor.fetch('mime_type'))
    supported = mime.start_with?('image/', 'audio/', 'video/') || Attachment::ACCEPTABLE_FILE_TYPES.include?(mime)
    valid = bytes.bytesize == descriptor.fetch('byte_size') && Digest::SHA256.hexdigest(bytes) == descriptor.fetch('sha256') &&
            mime == descriptor.fetch('mime_type') && supported
    raise ArgumentError, 'JRC_LIVE_MEDIA_INTEGRITY' unless valid
  end

  def verify_blob!(blob, descriptor)
    bytes = +''.b
    # Private, receiver-reserved blob only; no caller URL, public response or fallback.
    blob.download do |chunk|
      raise ArgumentError, 'JRC_LIVE_MEDIA_INTEGRITY' if chunk.bytesize > descriptor.fetch('byte_size') - bytes.bytesize

      bytes << chunk
    end
    verify_bytes!(bytes, descriptor)
  end

  def store!(receipt)
    blob = receipt.blob
    descriptor = receipt.envelope.fetch('media')
    # An existing object is immutable custody evidence. Never overwrite corruption.
    unless blob.service.exist?(blob.key)
      verify_bytes!(receipt.staged_bytes, descriptor)
      blob.service.upload(blob.key, StringIO.new(receipt.staged_bytes), checksum: blob.checksum)
    end
    verify_blob!(blob, descriptor)
  end
end
