# frozen_string_literal: true

require 'caxlsx'
require 'prawn'

class JrcServiceDesk::ManagerialReportFile
  MIME = JrcServiceDesk::ReportExportFile::MIME.merge('html' => 'text/html; charset=utf-8', 'csv' => 'text/csv; charset=utf-8').freeze

  def initialize(dataset, format)
    @dataset = dataset
    @format = format
    @labels = dataset.labels
  end

  def call
    raise ArgumentError unless JrcServiceDesk::ReportExport::MANAGERIAL_FORMATS.include?(@format)

    { data: send(@format), content_type: MIME.fetch(@format), filename: "JRC_ServiceDesk_#{@dataset.query.unit.id}_#{@dataset.observed_at.utc.strftime('%Y%m%d-%H%M%S')}.#{@format}" }
  end

  private

  def csv
    columns = @dataset.columns
    rows = @dataset.each_row.lazy.map { |row| columns.keys.map { |key| @dataset.detail(row, key) } }
    "\uFEFF#{JrcServiceDesk::OperationalCsv.generate(columns.values, rows)}"
  end

  def html
    path = Rails.root.join('app/views/jrc_service_desk/managerial_report_offline.html')
    payload = { labels: @labels, columns: @dataset.columns, rows: @dataset.each_row.to_a,
                locale: @dataset.locale.to_s.tr('_', '-'), criteria: @dataset.criteria,
                indicators: @dataset.metrics.present?, date_field: @dataset.query.date_field, group_by: @dataset.query.group_by }
    File.read(path, encoding: 'UTF-8').sub('__MANAGERIAL_REPORT_DATA__') { ERB::Util.json_escape(payload.to_json) }
  end

  def xlsx
    package = Axlsx::Package.new(use_shared_strings: true)
    book = package.workbook
    header = book.styles.add_style(bg_color: '063B7A', fg_color: 'FFFFFF', b: true)
    date_style = book.styles.add_style(format_code: 'yyyy-mm-dd hh:mm:ss')
    sheet(book, @labels[:summary], [@labels[:indicator], @labels[:amount]], @dataset.summary_rows, header)
    sheet(book, @labels[:criteria], [@labels[:indicator], @labels[:amount]], @dataset.criteria, header)
    ticket_sheet(book, header, date_style)
    if (metrics = @dataset.metrics)
      sheet(book, @labels[:volume], [@labels[:period], @labels[:total]], metrics[:volume][:items].map { |row| row.values_at(:day, :count) }, header)
      metrics[:dimensions].each do |field, data|
        rows = data[:items].map { |row| [@dataset.distribution_name(field, row), row[:count]] }
        sheet(book, @labels[:dimensions].fetch(field.to_sym), [@labels[:indicator], @labels[:total]], rows, header)
      end
      sheet(book, 'SLA', [@labels[:indicator], @labels[:state], @labels[:amount]], @dataset.sla_rows, header)
    end
    package.to_stream.read
  end

  def ticket_sheet(book, header, date_style)
    columns = @dataset.columns
    book.add_worksheet(name: @labels[:tickets]) do |tab|
      tab.add_row(columns.values, style: header)
      styles = columns.keys.map { |key| date_style if JrcServiceDesk::ManagerialReportDataset::DATE_COLUMNS.include?(key) }
      @dataset.each_row do |row|
        values = columns.keys.map do |key|
          value = @dataset.detail(row, key)
          if value && JrcServiceDesk::ManagerialReportDataset::DATE_COLUMNS.include?(key)
            DateTime.iso8601(value).change(offset: 0)
          else
            safe(value)
          end
        end
        tab.add_row(values, style: styles)
      end
      tab.auto_filter = "A1:#{Axlsx.col_ref(columns.length - 1)}#{tab.rows.length}"
      tab.sheet_view.pane do |pane|
        pane.top_left_cell = 'A2'
        pane.state = :frozen
        pane.y_split = 1
      end
      tab.column_widths(*columns.keys.map { |key| key == :title ? 54 : 25 })
    end
  end

  def sheet(book, name, headers, rows, style)
    book.add_worksheet(name: name.first(31)) do |tab|
      tab.add_row(headers, style: style)
      rows.each { |row| tab.add_row(row.map { |value| safe(value) }) }
      tab.auto_filter = "A1:#{Axlsx.col_ref(headers.length - 1)}#{tab.rows.length}"
      tab.column_widths(*headers.map { 28 })
    end
  end

  def safe(value)
    return value if value.is_a?(Numeric) || value.nil?

    JrcServiceDesk::OperationalCsv.cell(value)
  end

  def pdf
    document = Prawn::Document.new(page_size: 'A4', margin: 36)
    font = ENV['JRC_SD_REPORT_FONT'].presence || %w[/usr/share/fonts/dejavu/DejaVuSans.ttf
                                                    /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf].find { |path| File.file?(path) }
    raise ArgumentError, 'Report font unavailable' unless font && File.file?(font)

    document.font_families.update('Report' => { normal: font, bold: font.sub('.ttf', '-Bold.ttf') })
    document.font('Report')
    heading(document, @labels[:title], 22)
    @dataset.criteria.each { |label, value| document.text("#{label} · #{value}", size: 9, leading: 2) }
    heading(document, @labels[:summary])
    @dataset.summary_rows.each { |label, value| document.text("#{label} · #{value || @labels[:missing]}", size: 10) }
    pdf_distributions(document)
    heading(document, @labels[:sample])
    @dataset.each_row.take(20).each do |row|
      document.text("##{row[:id]} · #{row[:title]} · #{@dataset.detail(row, :phase)}", size: 9, leading: 2)
    end
    document.number_pages '<page> / <total>', at: [document.bounds.right - 70, -15], size: 9
    document.render
  end

  def pdf_distributions(document)
    return unless (metrics = @dataset.metrics)

    needs_note = metrics[:volume][:truncated] || metrics[:dimensions].values.any? { |data| data[:truncated] || data[:items].size > 12 }
    heading(document, @labels[:volume])
    draw_bars(document, metrics[:volume][:items].last(12).map { |row| row.values_at(:day, :count) })
    metrics[:dimensions].each do |key, data|
      next if data[:items].empty?

      heading(document, @labels[:dimensions].fetch(key.to_sym))
      draw_bars(document, data[:items].first(12).map { |row| [@dataset.distribution_name(key, row), row[:count]] })
    end
    document.text(@labels[:limited], size: 9) if needs_note || metrics[:volume][:items].size > 12
    heading(document, 'SLA')
    @dataset.sla_rows.each { |clock, label, value| document.text("#{clock} · #{label} · #{value || @labels[:missing]}", size: 9, leading: 2) }
  end

  def heading(document, title, size = 14)
    document.move_down(12)
    document.start_new_page if document.cursor < 55
    document.text(title, size: size, style: :bold)
    document.move_down(6)
  end

  def draw_bars(document, rows)
    largest = [rows.map(&:last).max.to_i, 1].max
    rows.each do |label, value|
      document.start_new_page if document.cursor < 34
      document.text("#{label.to_s.truncate(95)} · #{value}", size: 9)
      document.fill_color '0877E8'
      document.fill_rectangle([0, document.cursor - 2], 350.0 * value / largest, 7)
      document.fill_color '17304F'
      document.move_down(14)
    end
  end
end
