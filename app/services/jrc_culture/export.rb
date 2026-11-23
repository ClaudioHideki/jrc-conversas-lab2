# frozen_string_literal: true

require 'caxlsx'
require 'prawn'

class JrcCulture::Export
  HEADERS = ['Colaborador', 'Empresa', 'Unidade', 'Setor', 'Manual', 'Versão', 'Situação', 'Data da ciência'].freeze

  def initialize(rows)
    @rows = rows
  end

  def xlsx
    book = Axlsx::Package.new
    book.workbook.add_worksheet(name: 'Ciência') do |sheet|
      sheet.add_row(HEADERS)
      @rows.each { |row| sheet.add_row(values(row), types: Array.new(HEADERS.size, :string), escape_formulas: true) }
    end
    book.to_stream.read
  end

  def pdf
    font = ENV['JRC_SD_REPORT_FONT'].presence || %w[
      /usr/share/fonts/dejavu/DejaVuSans.ttf /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf
    ].find { |path| File.file?(path) }
    raise JrcCulture::Report::Invalid unless font && File.file?(font)

    document = Prawn::Document.new(page_size: 'A4')
    document.font(font)
    document.text('Manual de Cultura JRC', size: 19)
    document.move_down(10)
    @rows.each do |row|
      document.text(values(row).join(' | '), size: 9)
      document.move_down(6)
    end
    document.render
  end

  private

  def values(row)
    name = row[:collaborator] || "Usuário #{row[:user_id]}"
    confirmed = row[:confirmed_at]
    timestamp = confirmed&.in_time_zone(JrcCulture::Report::TIMEZONE)&.strftime('%d/%m/%Y %H:%M')
    [name, row[:company], row[:unit], row[:department], row[:title], row[:version].to_s,
     confirmed ? 'Ciência registrada' : 'Pendente', timestamp.to_s]
  end
end
