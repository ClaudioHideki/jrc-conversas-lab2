# frozen_string_literal: true

require 'zip'
require 'stringio'

class JrcCulture::Workbook
  class Invalid < StandardError; end

  LIMIT = 3.megabytes
  MAX_ROWS = 1_001
  KEY_HEADERS = %w[EMAIL USUARIO].freeze
  COLUMNS = [*KEY_HEADERS, 'SETOR', 'EMPRESA REGISTRADA'].freeze

  def self.rows(bytes)
    new.rows(bytes)
  rescue ArgumentError, Zip::Error, Nokogiri::XML::SyntaxError, KeyError, Zlib::Error
    raise Invalid
  end

  def rows(bytes)
    records = nil
    Zip::File.open_buffer(StringIO.new(bytes)) do |archive|
      shared = xml(archive, 'xl/sharedStrings.xml')&.xpath('//si')&.map { |row| row.xpath('.//t').map(&:text).join } || []
      sheet = xml(archive, sheet_path(archive))
      raise Invalid unless sheet

      values = sheet.xpath('//sheetData/row')
      raise Invalid unless values.size.between?(2, MAX_ROWS)

      headers = header_columns(cells(values.first, shared))
      records = values.drop(1).filter_map do |row|
        values_by_column = cells(row, shared)
        next if values_by_column.values.all?(&:blank?)

        fields = headers.transform_values { |column| values_by_column[column].to_s.strip }
        fields.merge('line' => Integer(row['r'], 10))
      end
    end
    records
  end

  private

  def sheet_path(archive)
    workbook = xml(archive, 'xl/workbook.xml')
    sheets = workbook&.xpath('//sheet')&.select { |row| row['state'].blank? || row['state'] == 'visible' } || []
    sheet = sheets.find { |row| row['name'] == 'Cadastro' } || (sheets.first if sheets.one?)
    raise Invalid unless sheet

    key = sheet.attribute_nodes.find { |node| node.name == 'id' }&.value
    relations = xml(archive, 'xl/_rels/workbook.xml.rels')
    row = relations&.xpath('//Relationship')&.find { |relationship| relationship['Id'] == key }
    target = row&.[]('Target').to_s.sub(%r{\A/?(?:xl/)?}, '')
    valid = row && row['TargetMode'] != 'External' && target.match?(%r{\Aworksheets/[a-zA-Z0-9_-]+\.xml\z})
    raise Invalid unless valid

    "xl/#{target}"
  end

  def xml(archive, path)
    entry = archive.find_entry(path)
    return unless entry
    raise Invalid if entry.size > LIMIT

    bytes = entry.get_input_stream { |stream| stream.read(LIMIT + 1) }
    raise Invalid if bytes.bytesize > LIMIT

    document = Nokogiri::XML(bytes) { |config| config.strict.nonet }
    raise Invalid if document.internal_subset

    document.remove_namespaces!
  end

  def cells(row, shared)
    row.xpath('./c').to_h do |cell|
      key = cell['r'].to_s[/\A[A-Z]{1,3}(?=\d+\z)/]
      raise Invalid unless key

      value = case cell['t']
              when 's'
                index = Integer(cell.at_xpath('./v')&.text, 10)
                raise Invalid if index.negative? || index >= shared.size

                shared.fetch(index)
              when 'inlineStr' then cell.xpath('./is//t').map(&:text).join
              else cell.at_xpath('./v')&.text.to_s
              end
      [key, value.first(500)]
    end
  end

  def header_columns(values)
    pairs = values.map { |column, value| [I18n.transliterate(value).strip.upcase, column] }.select { |name, _| COLUMNS.include?(name) }
    headers = pairs.to_h
    raise Invalid if pairs.size != headers.size || (headers.keys & KEY_HEADERS).empty?

    headers
  end
end
