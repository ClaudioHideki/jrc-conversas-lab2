require 'csv'
require 'digest'

# Parse the operator's file only. Record matching, permissions and writes belong
# to the reviewed import plan; even metadata inspection must not save a contact.
class JrcCustomers::ImportFile
  class InvalidFile < StandardError; end

  KINDS = %w[companies contacts both].freeze
  CONTACT_FIELDS = %w[id identifier name email phone_number company_id job_title department registration_status
                      company_role company_primary company_contact_status personal_tax_identifier labels].freeze
  DELIMITERS = [',', ';', "\t"].freeze
  MAX_HEADERS = 100

  attr_reader :headers, :delimiter, :sha256, :kind

  def initialize(content:, kind:, delimiter: nil)
    @kind = kind
    raise InvalidFile, 'Unsupported import type' unless KINDS.include?(kind)

    @content = validated_content(content)
    @sha256 = Digest::SHA256.hexdigest(content)

    @delimiter = delimiter || detect_delimiter
    raise InvalidFile, 'Unsupported CSV separator' unless DELIMITERS.include?(@delimiter)

    read_rows
  end

  def fields
    result = []
    result += JrcCustomers::CompanyImport::FIELDS.map { |field| "company.#{field}" } unless @kind == 'contacts'
    result += CONTACT_FIELDS.map { |field| "contact.#{field}" } unless @kind == 'companies'
    result
  end

  def metadata
    { headers: headers, row_count: @rows.size, delimiter: delimiter, sha256: sha256,
      fields: fields, suggested_mapping: headers.index_with { |header| suggested_field(header) } }
  end

  def mapped_rows(mapping)
    normalized = validate_mapping!(mapping)
    @rows.each_with_index.map do |values, index|
      mapped = { line: index + 2, company: {}, contact: {} }
      normalized.each do |header, field|
        next unless field

        entity, attribute = field.split('.', 2)
        mapped.fetch(entity.to_sym)[attribute] = values[header]
      end
      mapped
    end
  end

  private

  def validated_content(content)
    unless content.is_a?(String) && content.bytesize.between?(1, JrcCustomers::CompanyImport::MAX_BYTES)
      raise InvalidFile, 'CSV must contain between 1 byte and 1 MiB'
    end

    normalized = content.dup.force_encoding(Encoding::UTF_8).delete_prefix("\uFEFF")
    raise InvalidFile, 'CSV must be UTF-8 without null bytes' unless normalized.valid_encoding? && normalized.exclude?("\u0000")

    normalized
  end

  def read_rows
    table = parse(delimiter)
    @headers = validated_headers(table)
    raise InvalidFile, 'CSV must contain 1 to 500 records' unless table.size.between?(1, JrcCustomers::CompanyImport::MAX_ROWS)

    @rows = table.map do |row|
      raise InvalidFile, 'CSV row contains more values than its header' if row.fields.size > headers.size

      headers.zip(row.fields).to_h
    end
  end

  def validated_headers(table)
    raise InvalidFile, 'CSV requires a header row' unless table.headers.is_a?(Array)

    names = table.headers.map { |header| header.to_s.strip }
    if !names.size.between?(1, MAX_HEADERS) || names.any?(&:blank?) || names.uniq.size != names.size
      raise InvalidFile, 'CSV requires 1 to 100 nonempty, distinct column names'
    end

    names
  end

  def parse(separator)
    CSV.parse(@content, headers: true, skip_blanks: true, col_sep: separator, field_size_limit: 65_536)
  rescue CSV::MalformedCSVError
    raise InvalidFile, 'Malformed CSV; review quoting and separator'
  end

  def detect_delimiter
    candidates = DELIMITERS.filter_map do |separator|
      table = parse(separator)
      [separator, table.headers.size] if table.headers.is_a?(Array)
    rescue InvalidFile
      nil
    end
    raise InvalidFile, 'Malformed CSV; review quoting and separator' if candidates.empty?

    candidates.max_by(&:last).first
  end

  def suggested_field(header)
    return header if fields.include?(header)
    return nil if @kind == 'both'

    entity = @kind == 'companies' ? 'company' : 'contact'
    candidate = "#{entity}.#{header}"
    candidate if fields.include?(candidate)
  end

  def validate_mapping!(mapping)
    normalized = normalized_mapping(mapping)
    validate_destinations!(normalized.values.compact)
    normalized
  end

  def normalized_mapping(mapping)
    raise InvalidFile, 'Review every source column, including ignored columns' unless mapping.is_a?(Hash)

    normalized = mapping.stringify_keys.transform_values(&:presence)
    raise InvalidFile, 'Review every source column, including ignored columns' unless normalized.keys.sort == headers.sort

    normalized
  end

  def import_entities
    @kind == 'both' ? %w[company contact] : [@kind.singularize]
  end

  def validate_destinations!(selected)
    raise InvalidFile, 'Unsupported destination field' unless (selected - fields).empty?
    raise InvalidFile, 'Each destination field may be mapped only once' unless selected.uniq.size == selected.size
    raise InvalidFile, 'Choose at least one destination field' if selected.empty?

    return if import_entities.all? { |entity| selected.any? { |field| field.start_with?("#{entity}.") } }

    raise InvalidFile, 'Map the selected import types'
  end
end
