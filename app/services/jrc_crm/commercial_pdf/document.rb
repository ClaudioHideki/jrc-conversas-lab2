module JrcCrm
  module CommercialPdf
    class Document
      WIDTH = 595.276
      HEIGHT = 841.89
      attr_reader :pages

      class Page
        attr_reader :commands
        def initialize
          @commands = ''.b
        end
        def text(x, y, value, size: 10, bold: false, color: [0.12, 0.18, 0.25])
          return if value.to_s.empty?
          encoded = FontMetrics.encoded(value).gsub(/[\\()]/) { |char| "\\#{char}" }.b
          @commands << "#{color.join(' ')} rg BT /#{bold ? 'F2' : 'F1'} #{size} Tf #{format('%.3f', x)} #{format('%.3f', y)} Td (".b
          @commands << encoded << ") Tj ET\n".b
        end
        def fill_rect(x, y, width, height, color)
          @commands << "#{color.join(' ')} rg #{x} #{y} #{width} #{height} re f\n".b
        end
        def line(x1, y1, x2, y2, color:, width: 0.6)
          @commands << "#{color.join(' ')} RG #{width} w #{x1} #{y1} m #{x2} #{y2} l S\n".b
        end
        def logo(x, y, width, height)
          @commands << "q #{width} 0 0 #{height} #{x} #{y} cm /Logo Do Q\n".b
        end
      end

      def initialize(logo:)
        raise Logo::InvalidImage, 'O logo oficial JRC e obrigatorio.' unless logo && logo[:bytes] && !logo[:bytes].empty?
        @logo, @pages = logo, []
      end

      def add_page
        page = Page.new
        @pages << page
        page
      end

      def render
        objects = []
        add = ->(body) { objects << body.b; objects.length }
        catalog_id = add.call('')
        pages_id = add.call('')
        regular = add.call('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>')
        bold = add.call('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>')
        image = add.call("<< /Type /XObject /Subtype /Image /Width #{@logo[:width]} /Height #{@logo[:height]} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /#{@logo[:filter]} /Length #{@logo[:bytes].bytesize} >>\nstream\n".b + @logo[:bytes] + "\nendstream".b)
        page_ids = @pages.map do |page|
          stream = add.call("<< /Length #{page.commands.bytesize} >>\nstream\n".b + page.commands + "\nendstream".b)
          add.call("<< /Type /Page /Parent #{pages_id} 0 R /MediaBox [0 0 #{WIDTH} #{HEIGHT}] /Resources << /Font << /F1 #{regular} 0 R /F2 #{bold} 0 R >> /XObject << /Logo #{image} 0 R >> >> /Contents #{stream} 0 R >>")
        end
        objects[catalog_id - 1] = "<< /Type /Catalog /Pages #{pages_id} 0 R >>".b
        objects[pages_id - 1] = "<< /Type /Pages /Count #{page_ids.length} /Kids [#{page_ids.map { |id| "#{id} 0 R" }.join(' ')}] >>".b
        out = "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n".b
        offsets = [0]
        objects.each_with_index do |body, index|
          offsets << out.bytesize
          out << "#{index + 1} 0 obj\n".b << body << "\nendobj\n".b
        end
        xref = out.bytesize
        out << "xref\n0 #{objects.length + 1}\n0000000000 65535 f \n".b
        offsets.drop(1).each { |offset| out << format("%010d 00000 n \n", offset).b }
        out << "trailer\n<< /Size #{objects.length + 1} /Root #{catalog_id} 0 R >>\nstartxref\n#{xref}\n%%EOF\n".b
      end
    end
  end
end
