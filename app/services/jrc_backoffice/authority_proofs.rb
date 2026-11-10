# Normalizes declarations for review. Dates, basis or a checked box do not
# authorize a signer; all required people/evidence go to the native Central.
module JrcBackoffice::AuthorityProofs
  BASES = %w[self legal_representative power_of_attorney].freeze
  MAX_DOCUMENTS = 20
  MAX_TOTAL_BYTES = 100.megabytes

  module_function

  def normalize(value, roster)
    people = roster.fetch('signers').select { |person| person.fetch('required') }
    validate_size!(value, people)

    rows = value.map { |row| normalize_row(row, people, roster) }
    validate_collection!(rows, people)
    order = people.each_with_index.to_h { |person, index| [person.fetch('key'), index] }
    rows.sort_by { |row| order.fetch(row.fetch('signer_key')) }
  end

  def validate_size!(value, people)
    valid = value.is_a?(Array) && value.length == people.length && people.length.between?(2, 20)
    raise ArgumentError, 'Informe as evidências de representação de todos os assinantes obrigatórios.' unless valid
  end

  def validate_collection!(rows, people)
    raise ArgumentError, 'Represente cada assinante uma única vez.' unless rows.pluck('signer_key').uniq.length == people.length
    return if rows.flat_map { |row| row['document_version_ids'] }.uniq.length <= MAX_DOCUMENTS

    raise ArgumentError, 'Use até 20 documentos distintos na validação de poderes.'
  end

  def normalize_row(row, people, roster)
    raise ArgumentError, 'Informe a base, os documentos e a validade da representação.' unless row.is_a?(Hash)

    person = people.find { |entry| entry.fetch('key') == row['signer_key'] }
    raise ArgumentError, 'O assinante não pertence a esta versão.' unless person
    raise ArgumentError, 'Base de representação inválida.' unless BASES.include?(row['basis'])

    validate_self!(person, roster) if row['basis'] == 'self'
    { 'signer_key' => person.fetch('key'), 'basis' => row.fetch('basis'), 'reason' => reason!(row['reason']),
      'document_version_ids' => document_ids(row['document_version_ids']) }.merge(validity(row))
  end

  def reason!(value)
    raise ArgumentError, 'Justifique a representação de cada assinante.' unless value.is_a?(String) && value.strip.length.between?(1, 2000)

    value.strip
  end

  def document_ids(value)
    valid = value.is_a?(Array) && value.length.between?(1, 10) && value.all? do |id|
      id.to_s.match?(/\A[1-9]\d{0,18}\z/) && id.to_s.to_i <= 9_223_372_036_854_775_807
    end
    raise ArgumentError, 'Selecione de um a dez documentos versionados para cada pessoa.' unless valid

    value.map { |id| id.to_s.to_i }.uniq.sort
  end

  def validity(row)
    raise ArgumentError, 'Declare se a representação possui vencimento.' unless [true, false].include?(row['no_expiry'])

    first = date!(row['valid_from'])
    last = row['no_expiry'] ? nil : date!(row['valid_until'])
    raise ArgumentError, 'Validade da representação inconsistente.' if invalid_range?(first, last, row)

    { 'valid_from' => first.iso8601, 'valid_until' => last&.iso8601, 'no_expiry' => row['no_expiry'] }
  end

  def invalid_range?(first, last, row)
    (last && last < first) || (row['no_expiry'] && row['valid_until'].present?)
  end

  def date!(value)
    raise ArgumentError, 'Informe datas válidas no formato ano-mês-dia.' unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    Date.iso8601(value)
  rescue Date::Error
    raise ArgumentError, 'Informe datas válidas no formato ano-mês-dia.'
  end

  def validate_self!(person, roster)
    party = roster.fetch(person.fetch('party'))
    identifier = JrcCustomers::TaxIdentifier.normalize(party['tax_id'])
    return if party['person_kind'] == 'individual' && JrcCustomers::TaxIdentifier.cpf_valid?(identifier) &&
              identifier == person['personal_tax_identifier']

    raise ArgumentError, 'A representação em nome próprio exige a mesma pessoa física identificada no Cadastro Mestre.'
  end
end
