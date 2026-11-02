class JrcBackoffice::DocumentPreanalysis
  ANALYZER_VERSION = 'local-document-checks/1'.freeze

  def initialize(version)
    @version = version
  end

  def call
    return @version.analysis if @version.analysis

    # Parse exactly the verified bytes; do not reopen mutable storage between
    # the checksum check and the parser.
    bytes = JrcBackoffice::DocumentSafety.new(@version).bytes!
    extraction = Tempfile.create(['jrc-backoffice-evidence', '.bin']) do |file|
      file.binmode
      file.write(bytes)
      file.flush
      JrcBackoffice::TextExtraction.call(file.path, @version.file.content_type)
    end
    text = extraction.delete(:text)
    identifiers = text.scan(/(?:CNPJ)\s*[:\-]?\s*([A-Z0-9]{2}\.?[A-Z0-9]{3}\.?[A-Z0-9]{3}\/?[A-Z0-9]{4}-?\d{2})/i)
                      .flatten.map { |value| JrcCustomers::TaxIdentifier.normalize(value) }.uniq
    request = @version.backoffice_request
    company = request.account.master_companies.find_by(id: request.contact&.company_id)
    expected = JrcCustomers::TaxIdentifier.normalize(company&.tax_id)
    checksum = if identifiers.empty?
                 'not_found'
               elsif identifiers.all? { |value| JrcCustomers::TaxIdentifier.cnpj_valid?(value) }
                 'valid'
               else
                 'invalid'
               end
    comparison = if expected.blank?
                   'customer_unconfigured'
                 elsif identifiers.empty?
                   'not_found'
                 elsif identifiers.include?(expected)
                   'matches'
                 else
                   'mismatch'
                 end
    checks = { readable_text: text.strip.length >= 40, cnpj_checksum: checksum, customer_identifier: comparison }
    # No OCR confidence is invented for digital text. No legal/identity approval is automatic.
    @version.create_analysis!(analyzer_version: ANALYZER_VERSION,
      state: 'review_required', evidence: extraction.merge(checks: checks, characters: text.length, company_id: company&.id,
        review_required: true, scope: 'text_and_customer_identifier_only', analyzed_at: Time.current.iso8601))
  end
end
