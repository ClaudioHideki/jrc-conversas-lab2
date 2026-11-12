# frozen_string_literal: true

require 'caxlsx'
require 'prawn'

class JrcServiceDesk::ReportExportFile
  EXTRA_HEADERS = {
    'SLA' => ['Chamado', 'Compromisso', 'Estado', 'Resultado', 'Meta (s)', 'Tempo medido (s)', 'Limite', 'Conclusão', 'Base de tempo'],
    'OLA' => ['Chamado', 'Fila', 'Compromisso', 'Resultado', 'Meta (s)', 'Tempo medido (s)', 'Início', 'Fim'],
    'Pausas' => %w[Chamado Motivo Início Fim], 'Reaberturas' => ['Chamado', 'Data', 'Status de destino'],
    'Satisfação' => ['Chamado', 'Tipo', 'Nota normalizada', 'Data da resposta', 'Comentário autorizado']
  }.freeze
  MIME = { 'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'pdf' => 'application/pdf',
           'csv_summary' => 'text/csv; charset=utf-8', 'csv_detailed' => 'text/csv; charset=utf-8' }.freeze

  def initialize(dataset, format)
    @dataset = dataset
    @format = format
  end

  def call
    data = case @format
           when 'csv_summary', 'csv_detailed' then csv
           when 'xlsx' then xlsx
           when 'pdf' then pdf
           else raise ArgumentError, 'Unsupported file format'
           end
    { data: data, content_type: MIME.fetch(@format), filename: filename }
  end

  private

  def filename
    operator = @dataset.query.unit.operator_company.name.parameterize(separator: '_').presence || 'Empresa'
    period = %w[from to].map { |key| @dataset.query.filters[key].presence&.first(10) || 'Todos' }.join('_a_')
    extension = @format.start_with?('csv') ? 'csv' : @format
    "JRC_ServiceDesk_Chamados_#{operator}_#{period}_#{@format}.#{extension}"
  end

  def csv
    columns = @dataset.columns(@format)
    rows = @dataset.each_row.lazy.map { |row| columns.keys.map { |key| row[key] } }
    "\uFEFF#{JrcServiceDesk::OperationalCsv.generate(columns.values, rows)}"
  end

  def xlsx
    package = Axlsx::Package.new(author: @dataset.query.context.user.name, use_shared_strings: true)
    book = package.workbook
    header = book.styles.add_style(bg_color: '063B7A', fg_color: 'FFFFFF', b: true, alignment: { wrap_text: true })
    book.add_worksheet(name: 'Resumo') do |sheet|
      add_rows(sheet, @dataset.summary_rows, header)
      phases = @dataset.metrics.fetch(:phases)
      if phases.any?
        sheet.add_chart(Axlsx::BarChart, start_at: 'D2', end_at: 'M15') do |chart|
          chart.title = 'Chamados por fase — mesmo conjunto exportado'
          chart.add_series(data: sheet["B3:B#{2 + phases.length}"], labels: sheet["A3:A#{2 + phases.length}"])
        end
      end
    end
    columns = @dataset.columns('xlsx')
    book.add_worksheet(name: 'Chamados') do |sheet|
      sheet.add_row(columns.values, style: header)
      @dataset.collect_details = true
      @dataset.each_row { |row| sheet.add_row(columns.keys.map { |key| safe(row[key]) }) }
      sheet.auto_filter = "A1:#{Axlsx.col_ref(columns.length - 1)}#{sheet.rows.length}"
      sheet.sheet_view.pane do |pane|
        pane.top_left_cell = 'A2'
        pane.state = :frozen
        pane.y_split = 1
        pane.active_pane = :bottom_left
      end
      sheet.column_widths(*Array.new(columns.length, 24))
    end
    book.add_worksheet(name: 'Critérios da exportação') { |sheet| add_rows(sheet, [%w[Critério Valor]] + @dataset.criteria, header) }
    @dataset.extra.each do |name, rows|
      next if rows.empty?

      book.add_worksheet(name: name) { |sheet| add_rows(sheet, [EXTRA_HEADERS.fetch(name)] + rows, header) }
    end
    package.to_stream.read
  end

  def add_rows(sheet, rows, header)
    rows.each_with_index { |row, index| sheet.add_row(row.map { |value| safe(value) }, style: index.zero? ? header : nil) }
    sheet.column_widths(45, 62)
  end

  def safe(value)
    return value if value.nil? || value.is_a?(Numeric) || value == true || value == false

    JrcServiceDesk::OperationalCsv.cell(value.to_s.encode('UTF-8', invalid: :replace, undef: :replace).delete("\u0000"))
  end

  def pdf
    document = Prawn::Document.new(page_size: 'A4', margin: 36)
    font = ENV['JRC_SD_REPORT_FONT'].presence || %w[/usr/share/fonts/dejavu/DejaVuSans.ttf
                                                    /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf].find { |path| File.file?(path) }
    raise ArgumentError, 'Report font unavailable' unless font && File.file?(font)

    document.font_families.update('Report' => { normal: font, bold: font.sub('.ttf', '-Bold.ttf') })
    document.font('Report')
    document.fill_color '063B7A'
    document.text 'JRC Conversas — Relatório executivo', size: 20, style: :bold
    document.move_down 8
    document.fill_color '17304F'
    document.text "#{@dataset.query.unit.operator_company.name} / #{@dataset.query.unit.name}", size: 12
    document.text "Gerado em #{@dataset.stamp(@dataset.observed_at)} · #{@dataset.timezone}", size: 9
    document.move_down 16
    document.text "#{@dataset.count} chamados no conjunto autorizado", size: 16, style: :bold
    document.text 'Fases atuais dos chamados abertos no período selecionado', size: 10
    document.move_down 12
    chart(document)
    document.move_down 16
    document.text 'Indicadores oficiais de SLA', size: 14, style: :bold
    @dataset.metrics[:sla]&.each do |kind, values|
      completed = values[:completed]
      rate = completed.positive? ? format('%.1f%%', 100.0 * (completed - values[:completed_breached]) / completed) : 'Sem medição concluída'
      label = JrcServiceDesk::ReportExportData::CLOCK_LABELS.fetch(kind.to_sym)
      mean = values[:mean_elapsed_seconds] || 'não disponível'
      document.text "#{label}: #{completed} concluídos; #{rate}; média #{mean} s", size: 10
    end
    document.move_down 12
    document.text 'Principais serviços (quantidade de chamados)', size: 13, style: :bold
    @dataset.metrics.dig(:by_service, :items).first(10).each do |row|
      service = JrcServiceDesk::Service.find_by(account_id: @dataset.query.context.account.id, unit_id: @dataset.query.unit.id, id: row[:id])
      document.text "#{service&.name || 'Sem serviço'}: #{row[:count]}", size: 10
    end
    document.start_new_page
    document.text 'Critérios e rastreabilidade', size: 16, style: :bold
    @dataset.criteria.each { |key, value| document.text "#{key}: #{value}", size: 9, leading: 3 }
    document.move_down 12
    document.text 'Consulte a exportação Excel/CSV para o detalhamento completo dos chamados.', size: 10, style: :bold
    document.number_pages '<page> / <total>', at: [document.bounds.right - 70, -15], size: 9
    document.render
  end

  def chart(document)
    phases = @dataset.metrics.fetch(:phases)
    maximum = phases.values.max || 1
    phases.each do |phase, count|
      document.text "#{JrcServiceDesk::ReportExportData::PHASE_LABELS.fetch(phase)}: #{count}", size: 10
      document.fill_color '0877E8'
      document.fill_rectangle [0, document.cursor], 430.0 * count / [maximum, 1].max, 12
      document.move_down 20
      document.fill_color '17304F'
    end
  end
end
