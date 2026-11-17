require 'stringio'

class JrcBroker::MediaMime
  def self.detect(bytes, filename:, declared:)
    detected = Marcel::MimeType.for(StringIO.new(bytes), name: filename)
    return detected unless declared == 'audio/ogg' && detected == 'audio/opus' && ogg_opus_header?(bytes)

    # Same bytes and immutable descriptor: align Marcel's codec label with
    # the Broker's Ogg container label without rewriting the envelope/hash.
    'audio/ogg'
  end

  def self.ogg_opus_header?(bytes)
    bytes.bytesize >= 47 && bytes.byteslice(0, 4) == 'OggS' &&
      bytes.getbyte(4).zero? && bytes.getbyte(5) == 2 &&
      bytes.getbyte(26) == 1 && bytes.getbyte(27) == 19 &&
      bytes.byteslice(28, 8) == 'OpusHead' && bytes.getbyte(36) == 1 &&
      [1, 2].include?(bytes.getbyte(37)) && bytes.getbyte(46).zero?
  end
  private_class_method :ogg_opus_header?
end
