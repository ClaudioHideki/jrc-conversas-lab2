require 'stringio'
require 'vips'

class JrcCampaigns::BrokerImageNormalizer
  MAX_INPUT_BYTES = 10.megabytes
  MAX_OUTPUT_BYTES = 5.megabytes
  MAX_PIXELS = 20_000_000
  INVALID_WEBP = 'Imagem WebP inválida ou corrompida.'.freeze
  ANIMATED_WEBP = 'WebP animado não é suportado em imagens de campanha.'.freeze

  def self.call(kind:, file:)
    return file unless kind == 'image'

    if file.is_a?(ActiveStorage::Blob)
      raise ArgumentError, 'Imagem WebP maior que 10 MB.' if file.byte_size > MAX_INPUT_BYTES

      file.open { |io| normalize_io(file, io, file.filename.to_s, file.content_type) }
    else
      normalize_io(file, file.fetch(:io), file.fetch(:filename), file.fetch(:content_type))
    end
  end

  def self.normalize_io(original, io, filename, content_type)
    position = io.pos
    io.rewind
    signature = io.read(12).to_s
    declared_webp = content_type.to_s.split(';').first.to_s.strip.downcase == 'image/webp'
    return original unless webp_header?(signature) || declared_webp

    raise ArgumentError, INVALID_WEBP unless webp_header?(signature)

    io.rewind
    bytes = io.read(MAX_INPUT_BYTES + 1)
    raise ArgumentError, 'Imagem WebP maior que 10 MB.' if bytes.bytesize > MAX_INPUT_BYTES

    # Keep the derived stream alive for Active Storage's outer after_commit upload.
    { io: StringIO.new(png_bytes(bytes)), filename: "#{File.basename(filename.to_s, '.*')}.png", content_type: 'image/png' }
  ensure
    io.pos = position
  end

  def self.png_bytes(bytes)
    dimensions = verify_dimensions!(bytes)
    image = Vips::Image.new_from_buffer(bytes, '', access: :sequential, fail_on: :error)
    raise ArgumentError, ANIMATED_WEBP if image.get_typeof('n-pages').positive? && image.get('n-pages') > 1
    raise ArgumentError, INVALID_WEBP unless dimensions == [image.width, image.height]

    png = image.pngsave_buffer(strip: true)
    raise ArgumentError, 'Imagem PNG convertida maior que 5 MB.' if png.bytesize > MAX_OUTPUT_BYTES

    png
  rescue Vips::Error
    raise ArgumentError, INVALID_WEBP
  end

  def self.verify_dimensions!(bytes)
    dimensions = {}
    webp_chunks(bytes) do |type, payload|
      value = chunk_dimensions(type, payload)
      next unless value

      raise ArgumentError, 'Imagem WebP excede o limite de 20 milhões de pixels.' if value.reduce(:*) > MAX_PIXELS

      key = type == 'VP8X' ? :canvas : :frame
      raise ArgumentError, INVALID_WEBP if dimensions.key?(key)

      dimensions[key] = value
    end
    raise ArgumentError, INVALID_WEBP unless dimensions[:frame] && dimensions.values.uniq.one?

    dimensions[:frame]
  end

  # Only inspect bounded RIFF chunk headers before libvips can allocate a canvas.
  # Format reference: https://developers.google.com/speed/webp/docs/riff_container
  def self.webp_chunks(bytes)
    raise ArgumentError, INVALID_WEBP unless webp_header?(bytes) && bytes.byteslice(4, 4).unpack1('V') == bytes.bytesize - 8

    offset = 12
    while offset < bytes.bytesize
      type, payload, next_offset = webp_chunk(bytes, offset)
      yield type, payload
      offset = next_offset
    end
  end

  def self.webp_chunk(bytes, offset)
    header = bytes.byteslice(offset, 8)
    raise ArgumentError, INVALID_WEBP unless header.bytesize == 8

    size = header.byteslice(4, 4).unpack1('V')
    next_offset = offset + 8 + size + (size % 2)
    raise ArgumentError, INVALID_WEBP if next_offset > bytes.bytesize || (size.odd? && bytes.getbyte(next_offset - 1) != 0)

    [header.byteslice(0, 4), bytes.byteslice(offset + 8, [size, 10].min), next_offset]
  end

  def self.chunk_dimensions(type, payload)
    case type
    when 'VP8X' then extended_dimensions(payload)
    when 'VP8 ' then lossy_dimensions(payload)
    when 'VP8L' then lossless_dimensions(payload)
    when 'ANIM', 'ANMF' then raise ArgumentError, ANIMATED_WEBP
    end
  end

  def self.extended_dimensions(payload)
    raise ArgumentError, INVALID_WEBP unless payload.bytesize == 10
    raise ArgumentError, ANIMATED_WEBP if payload.getbyte(0).anybits?(2)

    [4, 7].map { |offset| "#{payload.byteslice(offset, 3)}\0".unpack1('V') + 1 }
  end

  def self.lossy_dimensions(payload)
    raise ArgumentError, INVALID_WEBP unless payload.bytesize == 10 && payload.byteslice(3, 3) == "\x9D\x01\x2A".b

    dimensions = payload.byteslice(6, 4).unpack('v2').map { |value| value & 0x3FFF }
    raise ArgumentError, INVALID_WEBP unless dimensions.all?(&:positive?)

    dimensions
  end

  def self.lossless_dimensions(payload)
    raise ArgumentError, INVALID_WEBP unless payload.bytesize >= 5 && payload.getbyte(0) == 0x2F

    value = payload.byteslice(1, 4).unpack1('V')
    [(value & 0x3FFF) + 1, ((value >> 14) & 0x3FFF) + 1]
  end

  def self.webp_header?(bytes)
    bytes.bytesize >= 12 && bytes.start_with?('RIFF') && bytes.byteslice(8, 4) == 'WEBP'
  end

  private_class_method :normalize_io, :png_bytes, :verify_dimensions!, :webp_chunks, :webp_chunk, :chunk_dimensions,
                       :extended_dimensions, :lossy_dimensions, :lossless_dimensions, :webp_header?
end
