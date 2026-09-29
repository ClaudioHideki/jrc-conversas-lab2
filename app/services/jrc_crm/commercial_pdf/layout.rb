module JrcCrm
  module CommercialPdf
    # A4 flow layout. Every line/item/term is retained, including unusually long
    # item descriptions; tables repeat their header across page boundaries.
    class Layout
      LEFT = 44.0
      WIDTH = Document::WIDTH - LEFT * 2
      BOTTOM = 76.0
      TOP = 722.0
      BLUE = [0.05, 0.27, 0.53].freeze
      PALE = [0.95, 0.97, 0.99].freeze
      TEXT = [0.12, 0.18, 0.25].freeze
      MUTED = [0.39, 0.44, 0.51].freeze
      BORDER = [0.84, 0.88, 0.92].freeze
      WHITE = [1, 1, 1].freeze

      def initialize(title:, number:, logo:)
        @title, @number, @logo = title, number.to_s, logo
        @document = Document.new(logo: logo)
        @table_header = nil
        new_page
      end

      def heading(text)
        paragraph(text, size: 17, bold: true, leading: 22, color: BLUE)
        @y -= 9
      end

      def section(text)
        # Keep the heading with at least the first table rows or paragraph.
        ensure_space(120)
        @y -= 7
        @page.text(LEFT, @y, text, size: 12, bold: true, color: BLUE)
        @page.line(LEFT, @y - 9, LEFT + WIDTH, @y - 9, color: BORDER)
        @y -= 27
      end

      def paragraph(text, size: 10, bold: false, leading: 15, color: TEXT)
        FontMetrics.wrap(text, width: WIDTH, size: size, bold: bold).each do |line|
          ensure_space(leading + 5)
          @page.text(LEFT, @y, line, size: size, bold: bold, color: color)
          @y -= leading
        end
        @y -= 6
      end

      def key_values(rows)
        table(rows, widths: [205, WIDTH - 205], headers: nil)
      end

      def table(rows, widths:, headers:)
        @table_widths = widths
        @table_header = headers
        ensure_space(75)
        draw_header if headers
        rows.each_with_index do |row, index|
          draw_row(row, widths: widths, stripe: index.odd?)
        end
        @table_header = nil
        @y -= 12
      end

      def signature_rows(customer, issuer)
        # Avoid leaving the heading/disclaimer on the page before the lines.
        ensure_space(180)
        section('Assinaturas')
        paragraph('Assinatura conforme o fluxo contratual registrado. Este PDF, isoladamente, nao comprova assinatura externa.', size: 9, color: MUTED)
        ensure_space(94)
        @y -= 34
        half = (WIDTH - 30) / 2
        @page.line(LEFT, @y, LEFT + half, @y, color: MUTED)
        @page.line(LEFT + half + 30, @y, LEFT + WIDTH, @y, color: MUTED)
        @y -= 16
        # Names remain complete and wrap underneath each signature line.
        left_lines = FontMetrics.wrap(customer, width: half, size: 8.5)
        right_lines = FontMetrics.wrap(issuer, width: half, size: 8.5)
        [left_lines.length, right_lines.length].max.times do |i|
          ensure_space(14)
          @page.text(LEFT, @y, left_lines[i], size: 8.5) if left_lines[i]
          @page.text(LEFT + half + 30, @y, right_lines[i], size: 8.5) if right_lines[i]
          @y -= 13
        end
      end

      def render
        @document.pages.each_with_index do |page, index|
          page.line(LEFT, 57, LEFT + WIDTH, 57, color: BORDER)
          page.text(LEFT, 41, 'JRC Conversas | Documento comercial', size: 8, color: MUTED)
          label = "Pagina #{index + 1} de #{@document.pages.length}"
          page.text(LEFT + WIDTH - FontMetrics.width(label, size: 8), 41, label, size: 8, color: MUTED)
        end
        @document.render
      end

      private

      def new_page
        @page = @document.add_page
        @page.fill_rect(0, Document::HEIGHT - 7, Document::WIDTH, 7, BLUE)
        @page.text(LEFT, 804, 'JRC CONVERSAS', size: 10, bold: true, color: BLUE)
        @page.text(LEFT, 777, @title, size: 21, bold: true, color: TEXT)
        @page.text(LEFT, 756, @number, size: 9, color: MUTED)
        logo_width = 83.0
        logo_height = logo_width * @logo[:height] / @logo[:width]
        @page.logo(LEFT + WIDTH - logo_width, 759, logo_width, logo_height)
        @page.line(LEFT, 743, LEFT + WIDTH, 743, color: BLUE, width: 1)
        @y = TOP
      end

      def ensure_space(height)
        return if @y - height >= BOTTOM
        new_page
      end

      def draw_header
        return unless @table_header
        height = 27
        @page.fill_rect(LEFT, @y - height, WIDTH, height, BLUE)
        x = LEFT
        @table_header.each_with_index do |value, i|
          @page.text(x + 7, @y - 17, value, size: 8, bold: true, color: WHITE)
          x += @table_widths[i]
        end
        @y -= height
      end

      def draw_row(values, widths:, stripe:)
        size, leading, padding = 9.2, 13.0, 14.0
        lines = values.each_with_index.map do |value, i|
          FontMetrics.wrap(value.to_s, width: widths[i] - 14, size: size)
        end
        remaining = lines.map(&:length).max || 1
        full_height = [remaining * leading + padding, 31].max
        fresh_height = TOP - BOTTOM - (@table_header ? 27 : 0)
        if full_height <= fresh_height && @y - full_height < BOTTOM
          new_page
          draw_header
        end
        offset = 0
        while remaining.positive?
          fit = ((@y - BOTTOM - padding) / leading).floor
          if fit < 1
            new_page
            draw_header
            fit = ((@y - BOTTOM - padding) / leading).floor
          end
          count = [remaining, fit].min
          height = [count * leading + padding, 31].max
          @page.fill_rect(LEFT, @y - height, WIDTH, height, stripe ? PALE : WHITE)
          x = LEFT
          values.each_index do |column|
            chunk = lines[column].slice(offset, count) || []
            chunk.each_with_index do |value, line|
              @page.text(x + 7, @y - 15 - line * leading, value, size: size, color: TEXT)
            end
            x += widths[column]
          end
          @page.line(LEFT, @y - height, LEFT + WIDTH, @y - height, color: BORDER, width: 0.4)
          @y -= height
          offset += count
          remaining -= count
          if remaining.positive?
            new_page
            draw_header
          end
        end
      end
    end
  end
end
