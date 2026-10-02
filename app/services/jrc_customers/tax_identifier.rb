# CNPJ accepts the numeric and alphanumeric formats; the last two positions
# remain numeric. Identifiers remain attributes, never primary keys.
module JrcCustomers::TaxIdentifier
  module_function

  def normalize(value)
    normalized = value.to_s.upcase.gsub(/[.\-\/\s]/, '')
    normalized.empty? ? nil : normalized
  end

  def valid?(value, person_kind: nil)
    value = normalize(value)
    return true if value.nil?
    return cpf_valid?(value) if person_kind == 'individual' || (person_kind.nil? && value.length == 11)

    cnpj_valid?(value)
  end

  def cpf_valid?(value)
    return false unless value.match?(/\A[0-9]{11}\z/) && value.chars.uniq.length > 1

    numbers = value.chars.map(&:to_i)
    first = checksum(numbers.take(9), (2..10).to_a.reverse)
    second = checksum(numbers.take(10), (2..11).to_a.reverse)
    numbers.last(2) == [first, second]
  end

  def cnpj_valid?(value)
    return false unless value.match?(/\A[A-Z0-9]{12}[0-9]{2}\z/) && value.chars.uniq.length > 1

    numbers = value.chars.map { |character| character.ord - 48 }
    first = checksum(numbers.take(12), [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2])
    second = checksum(numbers.take(13), [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2])
    numbers.last(2) == [first, second]
  end

  def checksum(numbers, weights)
    remainder = numbers.zip(weights).sum { |number, weight| number * weight } % 11
    remainder < 2 ? 0 : 11 - remainder
  end
end
