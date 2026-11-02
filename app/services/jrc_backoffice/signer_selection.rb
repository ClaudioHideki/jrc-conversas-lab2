# Validates a signing proposal only. No identity or documentary authority is
# granted here, and every selected person remains required in the proposal.
module JrcBackoffice::SignerSelection
  MODES = %w[single joint].freeze
  PARTIES = %w[customer issuer].freeze

  module_function

  def call(value, modes)
    validate_shape!(value, modes)
    rows = value.map { |entry| selection(entry) }
    raise ArgumentError, 'Uma pessoa não pode ocupar duas posições neste envio.' unless rows.pluck('contact_id').uniq.length == rows.length

    validate_counts!(rows, modes)
    rows
  end

  def validate_shape!(value, modes)
    raise ArgumentError, 'Selecione de 2 a 20 assinantes do Cadastro Mestre.' unless value.is_a?(Array) && value.length.between?(2, 20)

    valid_modes = modes.keys.sort == PARTIES.sort && modes.values.all? { |mode| MODES.include?(mode) }
    raise ArgumentError, 'Regra de assinatura inválida.' unless valid_modes
  end

  def selection(entry)
    raise ArgumentError, 'Selecione contatos canônicos e a parte representada.' unless entry.is_a?(Hash)

    reference = entry['contact_id'].to_s
    party = entry['party']
    valid = reference.match?(/\A[1-9]\d{0,18}\z/) && reference.to_i <= 9_223_372_036_854_775_807 && PARTIES.include?(party)
    raise ArgumentError, 'Selecione a parte e um contato cadastrado.' unless valid

    { 'contact_id' => reference.to_i, 'party' => party }
  end

  def validate_counts!(rows, modes)
    PARTIES.each do |party|
      count = rows.count { |row| row['party'] == party }
      valid = modes[party] == 'single' ? count == 1 : count.between?(2, 10)
      raise ArgumentError, 'Assinatura isolada exige uma pessoa; conjunta exige de duas a dez por parte.' unless valid
    end
  end
end
