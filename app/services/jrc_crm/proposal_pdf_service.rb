require 'mini_magick'
module JrcCrm
  class ProposalPdfService
    PAGE_WIDTH = 595.28
    PAGE_HEIGHT = 841.89
    BLUE = [0.027, 0.196, 0.357].freeze
    BLUE_2 = [0.035, 0.357, 0.650].freeze
    LIGHT_BLUE = [0.925, 0.958, 0.985].freeze
    TEXT = [0.075, 0.125, 0.180].freeze
    MUTED = [0.38, 0.43, 0.49].freeze
    WHITE = [1, 1, 1].freeze
    BORDER = [0.86, 0.88, 0.91].freeze

    def initialize(proposal)
      @proposal = proposal
      @deal = proposal.deal
      @contact = proposal.customer_contact
      @pages = []
    end

    def call
      build_cover
      build_solution_and_items
      build_commercial_conditions
      add_footers
      PdfDocument.new(@pages, logo: logo_data).render
    end

    private

    # Body content ends above 76pt; the footer occupies only 34-58pt.
    def new_section(title, top: 734)
      @section_title = title
      @page = standard_page(title)
      @pages << @page
      @y = top
    end

    def ensure_space(height)
      new_section(@section_title) if @y - height < 76
    end

    def paragraph(value, size: 10, bold: false, color: TEXT, leading: 16)
      Page.wrap(value, width: 499, size: size).each do |line|
        ensure_space(leading)
        @page.text(48, @y, line, size: size, bold: bold, color: color)
        @y -= leading
      end
      @y -= 10
    end

    def heading(value)
      ensure_space(58)
      paragraph(value, size: 11, bold: true, color: BLUE_2, leading: 18)
    end

    def build_cover
      new_section('Proposta comercial', top: 718)
      paragraph('JRC Conversas', size: 14, bold: true, color: BLUE)
      paragraph("#{@proposal.proposal_number} | VERSÃO #{@proposal.version_number}", bold: true, color: MUTED)
      paragraph(@proposal.title, size: 26, bold: true, color: BLUE, leading: 34)
      heading('Preparado para')
      paragraph(customer_name, size: 16, bold: true, leading: 23)
      paragraph("Validade: #{valid_until_text} | Vigência: #{@proposal.term_months} meses")
      heading('Apresentação')
      paragraph(@proposal.solution_description.presence || 'Solução comercial integrada para atendimento, relacionamento e resultados.',
                size: 12, color: MUTED, leading: 19)
    end

    def build_solution_and_items
      new_section('Solução e investimento')
      heading('Descrição da solução')
      paragraph(@proposal.solution_description.presence || 'Solução comercial JRC conforme escopo do negócio.')
      ensure_space(110)
      heading('Produtos e serviços')
      table_header
      items = @proposal.proposal_items.to_a
      paragraph('Nenhum produto adicionado.') if items.empty?
      items.each_with_index { |item, index| item_rows(item, index) }
    end

    TABLE_WIDTHS = [150, 62, 35, 64, 57, 57, 74].freeze
    TABLE_HEADERS = ['Produto / Serviço', 'Cobrança', 'Qtd.', 'Preço', 'Setup', 'Desc.', 'Total inicial'].freeze

    def table_header
      ensure_space(70)
      @page.fill_rect(48, @y - 28, 499, 28, BLUE_2)
      x = 48
      TABLE_HEADERS.each_with_index do |header, index|
        @page.text(x + 4, @y - 18, header, size: 6.7, bold: true, color: WHITE)
        x += TABLE_WIDTHS[index]
      end
      @y -= 28
    end

    def item_columns(item)
      description = [item.name_snapshot, item.description_snapshot]
      description << "Franquia #{item.included_quantity} #{item.included_unit}" if item.included_quantity.to_f.positive?
      amounts = [item.unit_price_cents, item.setup_fee_cents, item.applied_discount_cents, item.initial_total_cents].map { |cents| money(cents) }
      values = [description.compact.join("\n"), billing_label(item.billing_model), item.quantity.to_s, *amounts]
      values.each_with_index.map { |value, col| Page.wrap(value, width: TABLE_WIDTHS[col] - 8, size: 7) }
    end

    def item_rows(item, index)
      columns = item_columns(item)
      remaining = columns.map(&:length).max
      offset = 0
      # Keep ordinary rows together; only oversized descriptions span pages.
      if (remaining * 11) + 16 <= 630 && @y - ((remaining * 11) + 16) < 76
        new_section('Produtos e serviços (continuação)')
        table_header
      end
      while remaining.positive?
        if @y - 34 < 76
          new_section('Produtos e serviços (continuação)')
          table_header
        end
        count = [((@y - 76 - 16) / 11).floor, remaining].min
        height = (count * 11) + 16
        draw_item_segment(columns, offset, count, height, index)
        @y -= height
        offset += count
        remaining -= count
      end
    end

    def draw_item_segment(columns, offset, count, height, index)
      @page.fill_rect(48, @y - height, 499, height, index.even? ? WHITE : LIGHT_BLUE)
      @page.line(48, @y - height, 547, @y - height, color: BORDER, width: 0.6)
      x = 48
      columns.each_with_index do |lines, col|
        lines.slice(offset, count).to_a.each_with_index do |line, row|
          @page.text(x + 4, @y - 14 - (row * 11), line, size: 7, bold: col == 6, color: TEXT)
        end
        x += TABLE_WIDTHS[col]
      end
    end

    def build_commercial_conditions
      new_section('Condições comerciais')
      commercial_summary
      commercial_conditions
      heading('Observações comerciais')
      paragraph(@proposal.commercial_notes.presence ||
                'Condições sujeitas à validação comercial e técnica. Consumos variáveis e excedentes são faturados conforme utilização.')
      heading('Próximos passos')
      paragraph(@proposal.next_steps.presence ||
                "1. Aprovação comercial\n2. Alinhamento técnico\n3. Implantação e homologação\n4. Início da operação")
    end

    def commercial_summary
      @page.fill_rect(48, @y - 92, 499, 92, LIGHT_BLUE)
      @page.text(66, @y - 25, 'Mensalidade', size: 9, bold: true, color: MUTED)
      @page.text(66, @y - 53, money(@proposal.monthly_cents), size: 19, bold: true, color: BLUE)
      @page.text(300, @y - 25, 'Implantação', size: 9, bold: true, color: MUTED)
      @page.text(300, @y - 53, money(@proposal.implementation_cents), size: 19, bold: true, color: BLUE)
      @y -= 126
      commercial_totals
    end

    def commercial_totals
      heading('Resumo da proposta')
      commercial_row('Implantação', money(@proposal.implementation_cents))
      commercial_row('Recorrência mensal', money(@proposal.monthly_cents))
      commercial_row('Descontos nos itens', "- #{money(@proposal.item_discount_cents)}") if @proposal.item_discount_cents.positive?
      if @proposal.effective_general_discount_cents.positive?
        commercial_row('Desconto comercial adicional', "- #{money(@proposal.effective_general_discount_cents)}")
      end
      commercial_row('Total no primeiro mês', money(@proposal.total_cents), bold: true)
    end

    def commercial_conditions
      heading('Validade e condições')
      paragraph("Validade: #{valid_until_text} | Vigência: #{@proposal.term_months} meses")
      paragraph("Pagamento: #{@proposal.payment_method.presence || 'A definir'} | Vencimento: #{@proposal.billing_day.presence || 'A definir'}")
      paragraph(
        "Impostos: #{@proposal.taxes_included? ? 'inclusos' : 'não inclusos'} | " \
        "Reajuste: #{@proposal.annual_adjustment_index.presence || 'A definir'}"
      )
      paragraph("Renovação: #{renewal_label} | Multa de cancelamento: #{percentage(@proposal.cancellation_penalty_percent)}")
    end

    def commercial_row(label, value, bold: false)
      ensure_space(32)
      @page.text(48, @y, label, size: 10, bold: bold, color: bold ? BLUE : TEXT)
      @page.text(380, @y, value, size: 10, bold: bold, color: bold ? BLUE : TEXT)
      @page.line(48, @y - 10, 547, @y - 10, color: BORDER, width: 0.5)
      @y -= 32
    end

    def standard_page(title)
      page = Page.new
      page.fill_rect(0, 0, PAGE_WIDTH, PAGE_HEIGHT, WHITE)
      page.fill_rect(0, 0, 8, PAGE_HEIGHT, BLUE_2)
      page.logo(489, 776, 48, 48)
      page.text(48, 790, title, size: 20, bold: true, color: BLUE)
      page.line(48, 770, 547, 770, color: BLUE_2, width: 1.4)
      page
    end

    def add_footers
      @pages.each_with_index do |page, index|
        page.line(48, 58, 547, 58, color: BORDER)
        label = Page.wrap("JRC | #{customer_name}", width: 340, size: 8).first
        page.text(48, 40, label, size: 8, bold: true, color: MUTED)
        page.text(445, 40, "Página #{index + 1} de #{@pages.length}", size: 8, color: MUTED)
      end
    end

    def logo_data
      path = Rails.root.join('public', 'brand-assets', 'logo-jrc.png')
      return nil unless File.exist?(path)

      image = MiniMagick::Image.open(path.to_s)
      image.combine_options do |cmd|
        cmd.background 'white'
        cmd.alpha 'remove'
        cmd.alpha 'off'
      end
      image.format('jpg')
      width, height = image.dimensions
      { bytes: image.to_blob, width: width, height: height }
    rescue StandardError => e
      Rails.logger.warn("JRC CRM PDF logo fallback: #{e.message}")
      nil
    end

    def customer_name
      @contact&.name.presence || @deal.title
    end

    def valid_until_text
      (@proposal.valid_until || 15.days.from_now.to_date).strftime('%d/%m/%Y')
    end

    def billing_label(value)
      {
        'one_time' => 'Única',
        'monthly' => 'Mensal',
        'annual' => 'Anual',
        'usage' => 'Por uso'
      }.fetch(value.to_s, value.to_s)
    end

    def renewal_label
      {
        'automatic' => 'automática',
        'manual' => 'manual',
        'none' => 'sem renovação'
      }.fetch(@proposal.renewal_type.to_s, @proposal.renewal_type.to_s)
    end

    def percentage(value)
      ActionController::Base.helpers.number_to_percentage(value.to_f, precision: 2, strip_insignificant_zeros: true)
    end

    def money(cents)
      ActionController::Base.helpers.number_to_currency(cents.to_i / 100.0, unit: 'R$ ', separator: ',', delimiter: '.')
    end

    class Page
      attr_reader :commands

      def initialize
        @commands = ''.b
      end

      def text(x, y, value, size: 11, bold: false, color: TEXT)
        return if value.blank?

        @commands << color_cmd(color)
        @commands << "BT /#{bold ? 'F2' : 'F1'} #{size} Tf #{fmt(x)} #{fmt(y)} Td (#{escape(value)}) Tj ET\n".b
      end

      def fill_rect(x, y, width, height, color)
        @commands << color_cmd(color)
        @commands << "#{fmt(x)} #{fmt(y)} #{fmt(width)} #{fmt(height)} re f\n".b
      end

      def line(x1, y1, x2, y2, color:, width: 1)
        @commands << stroke_color_cmd(color)
        @commands << "#{fmt(width)} w #{fmt(x1)} #{fmt(y1)} m #{fmt(x2)} #{fmt(y2)} l S\n".b
      end

      def logo(x, y, width, height)
        @commands << "q #{fmt(width)} 0 0 #{fmt(height)} #{fmt(x)} #{fmt(y)} cm /Logo Do Q\n".b
      end

      # Conservative widths bound Helvetica regular/bold, including Latin accents.
      def self.text_width(value, size)
        value.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').each_char.sum do |char|
          factor = if 'MWmw@%'.include?(char)
                     1.0
                   elsif char.match?(/[A-Z]/)
                     0.78
                   else
                     0.64
                   end
          factor * size
        end
      end

      def self.wrap(value, width:, size:)
        value.to_s.split("\n", -1).flat_map do |paragraph|
          lines = ['']
          paragraph.split.each do |word|
            candidate = lines.last.empty? ? word : "#{lines.last} #{word}"
            if text_width(candidate, size) <= width
              lines[-1] = candidate
              next
            end
            lines << '' unless lines.last.empty?
            word.each_char do |char|
              lines << '' if text_width(lines.last + char, size) > width
              lines[-1] += char
            end
          end
          lines
        end
      end

      private

      def escape(value)
        value.to_s.encode(Encoding::Windows_1252, invalid: :replace, undef: :replace, replace: '?')
             .gsub('\\', '\\\\').gsub('(', '\\(').gsub(')', '\\)')
             .force_encoding(Encoding::BINARY)
      end

      def color_cmd(color)
        "#{color.map { |v| fmt(v) }.join(' ')} rg\n".b
      end

      def stroke_color_cmd(color)
        "#{color.map { |v| fmt(v) }.join(' ')} RG\n".b
      end

      def fmt(value)
        format('%.3f', value.to_f).sub(/\.0+$/, '').sub(/(\.\d*?)0+$/, '\\1')
      end
    end

    class PdfDocument
      def initialize(pages, logo: nil)
        @pages = pages
        @logo = logo
      end

      def render
        objects = []
        add = ->(body) { objects << body.b; objects.length }

        catalog_id = add.call('')
        pages_id = add.call('')
        font_regular_id = add.call('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>')
        font_bold_id = add.call('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>')
        logo_id = @logo ? add.call(logo_object(@logo)) : nil

        page_ids = []
        @pages.each do |page|
          content = page.commands.dup
          content.gsub!('/Logo Do'.b, ''.b) unless logo_id
          content_id = add.call(stream_object(content))
          resources = "<< /Font << /F1 #{font_regular_id} 0 R /F2 #{font_bold_id} 0 R >>"
          resources += " /XObject << /Logo #{logo_id} 0 R >>" if logo_id
          resources += ' >>'
          page_id = add.call("<< /Type /Page /Parent #{pages_id} 0 R /MediaBox [0 0 #{PAGE_WIDTH} #{PAGE_HEIGHT}] " \
                             "/Resources #{resources} /Contents #{content_id} 0 R >>")
          page_ids << page_id
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
        out << "xref\n0 #{objects.length + 1}\n".b
        out << "0000000000 65535 f \n".b
        offsets.drop(1).each { |offset| out << format("%010d 00000 n \n", offset).b }
        out << "trailer\n<< /Size #{objects.length + 1} /Root #{catalog_id} 0 R >>\nstartxref\n#{xref}\n%%EOF\n".b
        out
      end

      private

      def stream_object(content)
        "<< /Length #{content.bytesize} >>\nstream\n".b + content + "\nendstream".b
      end

      def logo_object(logo)
        bytes = logo[:bytes].dup.force_encoding(Encoding::BINARY)
        header = (
          "<< /Type /XObject /Subtype /Image /Width #{logo[:width]} /Height #{logo[:height]} " \
            "/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length #{bytes.bytesize} >>\nstream\n"
        ).b
        header + bytes + "\nendstream".b
      end
    end
  end
end
