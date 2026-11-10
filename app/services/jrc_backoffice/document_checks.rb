# Text-only assistance over bytes already checked by DocumentSafety.
# Identifiers are used in memory and are never returned in evidence or logs.
class JrcBackoffice::DocumentChecks
  PATTERNS = {
    'cnpj' => /(?:\bCNPJ)\s*[:\-]?\s*([A-Z0-9]{2}\.?[A-Z0-9]{3}\.?[A-Z0-9]{3}\/?[A-Z0-9]{4}-?\d{2})(?![A-Z0-9])/i,
    'cpf' => /(?:\bCPF)\s*[:\-]?\s*([0-9]{3}\.?[0-9]{3}\.?[0-9]{3}-?[0-9]{2})(?![0-9])/i
  }.freeze

  def self.call(text:, expected_identifier:)
    raise ArgumentError, 'Extracted text is required' unless text.is_a?(String)

    identifiers = PATTERNS.transform_values do |pattern|
      text.scan(pattern).flatten.map { |value| JrcCustomers::TaxIdentifier.normalize(value) }.uniq
    end
    expected = JrcCustomers::TaxIdentifier.normalize(expected_identifier)
    # A missing identifier is not a failed identity check and is never a pass.
    kind = if expected && JrcCustomers::TaxIdentifier.cpf_valid?(expected)
             'cpf'
           elsif expected && JrcCustomers::TaxIdentifier.cnpj_valid?(expected)
             'cnpj'
           end
    comparison = if expected.nil?
                   'customer_unconfigured'
                 elsif kind.nil?
                   'customer_invalid'
                 elsif identifiers.fetch(kind).empty?
                   'not_found'
                 elsif !identifiers.fetch(kind).include?(expected)
                   'mismatch'
                 elsif identifiers.fetch(kind).length > 1
                   'ambiguous'
                 else
                   'matches'
                 end
    { readable_text: text.strip.length >= 40,
      cnpj_checksum: checksum(identifiers.fetch('cnpj'), :cnpj_valid?),
      cpf_checksum: checksum(identifiers.fetch('cpf'), :cpf_valid?),
      customer_identifier: comparison }
  end

  def self.checksum(values, predicate)
    return 'not_found' if values.empty?

    values.all? { |value| JrcCustomers::TaxIdentifier.public_send(predicate, value) } ? 'valid' : 'invalid'
  end
  private_class_method :checksum
end
