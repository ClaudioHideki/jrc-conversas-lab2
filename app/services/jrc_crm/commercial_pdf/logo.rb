require 'zlib'

module JrcCrm
  module CommercialPdf
    # Read the official PNG directly. No missing fallback and no silent logo loss.
    # Supports the BASE's 8-bit RGB/RGBA, non-interlaced PNG. Alpha is composited
    # over white; the original asset is never modified.
    class Logo
      class InvalidImage < IOError; end
      SIGNATURE = "\x89PNG\r\n\x1a\n".b.freeze
      def self.load(path)
        bytes = File.binread(path)
        raise InvalidImage, 'Logo JRC: assinatura PNG invalida.' unless bytes.start_with?(SIGNATURE)
        offset = 8
        compressed = ''.b
        width = height = color = nil
        ended = false
        while offset < bytes.bytesize
          raise InvalidImage, 'Logo JRC: chunk incompleto.' if offset + 12 > bytes.bytesize
          size = bytes.byteslice(offset, 4).unpack1('N')
          type = bytes.byteslice(offset + 4, 4)
          data = bytes.byteslice(offset + 8, size)
          crc = bytes.byteslice(offset + 8 + size, 4)
          raise InvalidImage, 'Logo JRC: chunk/CRC invalido.' unless data && crc && crc.bytesize == 4 && Zlib.crc32(type + data) == crc.unpack1('N')
          if type == 'IHDR'
            width, height, depth, color, compression, filter, interlace = data.unpack('NNCCCCC')
            unless depth == 8 && [2, 6].include?(color) && compression.zero? && filter.zero? && interlace.zero?
              raise InvalidImage, 'Logo JRC deve ser PNG RGB/RGBA 8-bit sem entrelacamento.'
            end
          elsif type == 'IDAT'
            compressed << data
          elsif type == 'IEND'
            ended = true
            break
          end
          offset += 12 + size
        end
        raise InvalidImage, 'Logo JRC: imagem incompleta.' unless ended && width && height && width.positive? && height.positive? && width * height <= 4_000_000
        channels = color == 6 ? 4 : 3
        stride = width * channels
        raw = Zlib.inflate(compressed)
        raise InvalidImage, 'Logo JRC: tamanho inesperado.' unless raw.bytesize == height * (stride + 1)
        rgb = ''.b
        previous = Array.new(stride, 0)
        height.times do |y|
          start = y * (stride + 1)
          filter = raw.getbyte(start)
          raise InvalidImage, 'Logo JRC: filtro desconhecido.' unless (0..4).cover?(filter)
          line = raw.byteslice(start + 1, stride).bytes
          stride.times do |x|
            a = x >= channels ? line[x - channels] : 0
            b = previous[x]
            c = x >= channels ? previous[x - channels] : 0
            predictor = case filter
                        when 0 then 0
                        when 1 then a
                        when 2 then b
                        when 3 then (a + b) / 2
                        else paeth(a, b, c)
                        end
            line[x] = (line[x] + predictor) & 255
          end
          line.each_slice(channels) do |pixel|
            alpha = channels == 4 ? pixel[3] : 255
            rgb << pixel.first(3).map { |v| (v * alpha + 255 * (255 - alpha) + 127) / 255 }.pack('C*')
          end
          previous = line
        end
        { width: width, height: height, bytes: Zlib::Deflate.deflate(rgb), filter: 'FlateDecode' }.freeze
      rescue Errno::ENOENT, Zlib::Error => e
        raise InvalidImage, "Logo oficial JRC indisponivel: #{e.message}"
      end

      def self.paeth(a, b, c)
        p = a + b - c
        pa, pb, pc = (p - a).abs, (p - b).abs, (p - c).abs
        pa <= pb && pa <= pc ? a : (pb <= pc ? b : c)
      end
    end
  end
end
