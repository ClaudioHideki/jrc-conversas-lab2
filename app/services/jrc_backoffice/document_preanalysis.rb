class JrcBackoffice::DocumentPreanalysis
  ANALYZER_VERSION = 'local-document-checks/2'.freeze

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
    request = @version.backoffice_request
    company = request.account.master_companies.find_by(id: request.contact&.company_id)
    checks = JrcBackoffice::DocumentChecks.call(text: text, expected_identifier: company&.tax_id)
    # No OCR confidence is invented for digital text. No legal/identity approval is automatic.
    @version.create_analysis!(analyzer_version: ANALYZER_VERSION,
      state: 'review_required', evidence: extraction.merge(checks: checks, characters: text.length, company_id: company&.id,
        review_required: true, scope: 'cpf_cnpj_crosscheck_only', analyzed_at: Time.current.iso8601))
  end
end
