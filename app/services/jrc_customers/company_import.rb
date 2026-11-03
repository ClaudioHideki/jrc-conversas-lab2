require 'csv'
require 'digest'

# Companies use the master table. Contact CSV imports keep Chatwoot's existing job.
# Preview is read-only; apply requires the exact file and signed, actor/account-bound preview.
class JrcCustomers::CompanyImport
  class InvalidImport < StandardError
    attr_reader :field, :code

    def initialize(message = nil, field: nil, code: 'INVALID_COMPANY')
      super(message)
      @field = field
      @code = code
    end
  end
  FIELDS = %w[id name person_kind trade_name tax_id state_registration municipal_registration segment size website domain email
              phone_number source economic_group parent_company_id owner_id relationship_type active description].freeze
  MAX_BYTES = 1_048_576
  MAX_ROWS = 500
  REFERENCE_FIELDS = %w[parent_company_id owner_id].freeze
  BOOLEAN_VALUES = %w[true false].freeze

  def initialize(account:, actor:, content:)
    @account = account
    @actor = actor
    @content = content
    @coverage = JrcCrm::CorporateCoverage.new(account: account, user: actor)
    raise InvalidImport, 'CSV exceeds 1 MiB' if content.bytesize > MAX_BYTES

    @content = content.dup.force_encoding(Encoding::UTF_8).delete_prefix("\uFEFF")
    raise InvalidImport, 'CSV must be valid UTF-8' unless @content.valid_encoding?
  end

  def preview
    result = plan
    result.merge(token: result[:errors].empty? ? verifier.generate(envelope(result), expires_in: 15.minutes) : nil,
                 max_rows: MAX_ROWS, expires_in_seconds: 900)
  end

  def apply!(token:)
    raise InvalidImport, 'Invalid preview token' unless token.is_a?(String) && token.bytesize <= 4096

    payload = verifier.verified(token)
    received = payload.is_a?(Hash) ? payload.with_indifferent_access : nil
    raise InvalidImport, 'Preview expired or invalid; preview again' unless received

    @account.with_lock do
      result = plan
      raise InvalidImport, 'File, user or records changed since preview; preview again' unless received == envelope(result).with_indifferent_access
      raise InvalidImport, 'Resolve all preview errors before applying' if result[:errors].any?

      ids = result[:rows].map do |row|
        company = row[:company_id] ? @account.master_companies.find(row[:company_id]) : @account.master_companies.new
        JrcCustomers::CompanyWriter.new(account: @account, actor: @actor).save!(company: company, attributes: row[:attributes])
        company.id
      end
      if ids.any?
        JrcCustomers::Audit.record!(account: @account, actor: @actor, resource: @account.master_companies.find(ids.first),
                                    event_type: 'customer_import_applied', metadata: { sha256: Digest::SHA256.hexdigest(@content), company_ids: ids })
      end
      { applied: ids.length, company_ids: ids }
    end
  end

  private

  def verifier
    Rails.application.message_verifier('jrc_customer_master_import')
  end

  def envelope(result)
    { account_id: @account.id, actor_id: @actor.id, sha256: Digest::SHA256.hexdigest(@content),
      plan_sha256: Digest::SHA256.hexdigest(JSON.generate(result)) }
  end

  def plan
    parsed = CSV.parse(@content, headers: true, skip_blanks: true, field_size_limit: 65_536)
    raise InvalidImport, "Maximum #{MAX_ROWS} rows" if parsed.size > MAX_ROWS
    raise InvalidImport, 'CSV is empty' if parsed.empty?

    headers = Array(parsed.headers).map { |header| header.to_s.strip }
    unless headers.include?('name') && (headers - FIELDS).empty? && headers.uniq.size == headers.size
      raise InvalidImport,
            'CSV must contain name and only supported headers; duplicate headers are not allowed'
    end

    seen_ids = []
    seen_tax = []
    seen_domains = []
    result = { rows: [], errors: [] }
    parsed.each_with_index do |row, index|
      attrs = row.to_h.transform_keys { |key| key.to_s.strip }.transform_values { |value| value.to_s.strip.presence }
      id = attrs.delete('id')
      tax = JrcCustomers::TaxIdentifier.normalize(attrs['tax_id'])
      company = id.present? ? @account.master_companies.find(integer_reference(id, 'id')) : nil
      by_tax = tax.present? ? @account.master_companies.find_by(tax_id: tax) : nil
      invalid!('ID and CPF/CNPJ point to different companies', field: 'id') if company && by_tax && company.id != by_tax.id

      company ||= by_tax
      if company.nil? && @account.master_companies.where('lower(name) = ?', attrs['name'].to_s.downcase).exists?
        invalid!('Matching name is not an identity: supply the existing id or review the company name', field: 'name')
      end
      invalid!('Same company appears more than once in CSV', field: 'id') if company && seen_ids.include?(company.id)
      invalid!('Repeated CPF/CNPJ in CSV', field: 'tax_id') if tax && seen_tax.include?(tax)

      domain = attrs['domain']&.downcase
      invalid!('Repeated domain in CSV', field: 'domain') if domain && seen_domains.include?(domain)

      seen_ids << company.id if company
      seen_tax << tax if tax
      seen_domains << domain if domain
      REFERENCE_FIELDS.each { |key| attrs[key] = integer_reference(attrs[key], key) if attrs[key].present? }
      if attrs.key?('active')
        invalid!('active must be true or false', field: 'active') unless BOOLEAN_VALUES.include?(attrs['active'])

        attrs['active'] = attrs['active'] == 'true'
      end
      company ||= @account.master_companies.new(relationship_type: 'prospect')
      attrs['relationship_type'] ||= company.relationship_type
      original_stamp = company.persisted? ? company.updated_at.iso8601(6) : nil
      company.assign_attributes(attrs)
      @coverage.authorize_company_write!(company)
      validate_company!(company)

      result[:rows] << { line: index + 2, action: company.persisted? ? 'update' : 'create', company_id: company.id,
                         updated_at: original_stamp, attributes: attrs }
    rescue InvalidImport, ActiveRecord::RecordNotFound, ArgumentError => e
      result[:errors] << row_error(e, index + 2)
    end
    result
  rescue CSV::MalformedCSVError => e
    raise InvalidImport, e.message
  end

  def validate_company!(company)
    return if company.valid?

    invalid!(company.errors.full_messages.join('; '), field: company.errors.attribute_names.first.to_s)
  end

  def integer_reference(value, field)
    Integer(value, 10)
  rescue ArgumentError => e
    invalid!(e.message, field: field, code: 'INVALID_REFERENCE')
  end

  def invalid!(message, field:, code: 'INVALID_COMPANY')
    raise InvalidImport.new(message, field: field, code: code)
  end

  def row_error(error, line)
    code = error.is_a?(ActiveRecord::RecordNotFound) ? 'UNAVAILABLE_RECORD' : 'INVALID_REFERENCE'
    return { line: line, error: error.message, field: nil, code: code } unless error.is_a?(InvalidImport)

    { line: line, error: error.message, field: error.field, code: error.code }
  end
end
