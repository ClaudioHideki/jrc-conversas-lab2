# Optional numeric bands captured with the score, never inferred for historical actions.
class JrcRelationship::PriorityBands
  CODES = %w[P0 P1 P2 P3].freeze
  KEYS = %w[priority_band priority_band_score priority_band_minimum priority_band_policy].freeze

  def self.validation_errors(rules)
    validate!(rules['priority_bands']) if rules.key?('priority_bands')
    []
  rescue ArgumentError => e
    [e.message]
  end

  def self.validate!(bands)
    return if bands == []

    valid = bands.is_a?(Array) && bands.size == CODES.size && bands.each_with_index.all? { |row, index| valid_row?(row, CODES[index]) }
    valid &&= descending?(bands)
    raise ArgumentError, 'priority bands require P0 through P3 with descending integer minima from 0 to 100 and P3 at zero' unless valid
  end

  def self.valid_row?(row, code)
    row.is_a?(Hash) && row.keys.sort == %w[code minimum] && row['code'] == code &&
      row['minimum'].is_a?(Integer) && row['minimum'].between?(0, 100)
  end

  def self.descending?(bands)
    bands.last['minimum'].zero? && bands.each_cons(2).all? { |left, right| left['minimum'] > right['minimum'] }
  end
  private_class_method :valid_row?, :descending?

  def self.capture(factors, score, bands)
    values = factors.except(*KEYS)
    return values if bands.nil? || bands == []

    validate!(bands)
    return values unless score.is_a?(Integer) && score.between?(0, 100)

    selected = bands.find { |row| score >= row.fetch('minimum') }
    values.merge('priority_band' => selected.fetch('code'), 'priority_band_score' => score,
                 'priority_band_minimum' => selected.fetch('minimum'), 'priority_band_policy' => bands.to_json)
  end

  def self.refresh_captured(factors, score)
    return factors unless factors['priority_band_policy']

    capture(factors, score, JSON.parse(factors.fetch('priority_band_policy')))
  end
end
