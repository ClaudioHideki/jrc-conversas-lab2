# Version 2 selects native steps without changing v1 or captured plans.
class JrcApprovals::TierRanges
  KEYS = %w[field currency min max coverage rows].freeze
  ROW_KEYS = %w[min max min_inclusive max_inclusive step_codes].freeze
  BOOLEANS = [true, false].freeze
  MAX_EXACT_BOUND = 9_007_199_254_740_991

  def initialize(definition, entry)
    @definition = definition
    @tiers = definition.fetch('tiers')
    @step_codes = definition.fetch('steps').pluck('code')
    @type = entry.fields[@tiers['field']] if @tiers.is_a?(Hash)
  end

  def validate!
    validate_header!
    @domain = interval(@tiers, closed: true)
    invalid! unless @domain.valid?
    @ranges = @tiers['rows'].map { |row| validate_row!(row) }
    mapped = @tiers['rows'].flat_map { |row| row['step_codes'] }.uniq.sort
    invalid! unless mapped == @step_codes.sort
    @ranges.each_cons(2) { |left, right| validate_adjacent!(left, right) }
    validate_coverage! if @tiers['coverage'] == 'complete'
    true
  end

  def steps!(values)
    validate!
    actual = number(values.fetch(@tiers['field']))
    index = @ranges.index { |range| range.contains?(actual) } if @domain.contains?(actual)
    raise JrcApprovals::Error, 'TIER_NOT_APPLICABLE' if index.nil?

    codes = @tiers['rows'][index].fetch('step_codes')
    @definition.fetch('steps').select { |step| codes.include?(step['code']) }
  end

  private

  def validate_header!
    invalid! unless @tiers.is_a?(Hash) && @tiers.keys.sort == KEYS.sort
    invalid! unless valid_type_and_currency?
    invalid! unless %w[complete partial].include?(@tiers['coverage'])
    invalid! unless @tiers['rows'].is_a?(Array) && @tiers['rows'].size.between?(1, 16)
  end

  def valid_type_and_currency?
    return false unless %w[integer decimal money].include?(@type)

    @type == 'money' ? @tiers['currency'].is_a?(String) && @tiers['currency'].match?(/\A[A-Z]{3}\z/) : @tiers['currency'].nil?
  end

  def number(value)
    typed = JrcApprovals::Conditions.value!(@type, value)
    return typed unless @type == 'money'

    invalid! unless typed.first == @tiers['currency']
    typed.last
  end

  def interval(row, closed: false)
    lower = bound(row['min']) unless row['min'].nil?
    upper = bound(row['max']) unless row['max'].nil?
    included = closed ? [!lower.nil?, !upper.nil?] : row.values_at('min_inclusive', 'max_inclusive')
    JrcApprovals::TierInterval.new(lower, upper, *included)
  end

  def bound(value)
    typed = number(value)
    invalid! if typed.is_a?(Integer) && typed.abs > MAX_EXACT_BOUND
    typed
  end

  def validate_row!(row)
    invalid! unless row.is_a?(Hash) && row.keys.sort == ROW_KEYS.sort
    invalid! unless %w[min_inclusive max_inclusive].all? { |key| BOOLEANS.include?(row[key]) }
    range = interval(row)
    invalid! unless range.valid? && @domain.covers?(range)
    validate_codes!(row['step_codes'])
    range
  end

  def validate_codes!(codes)
    invalid! unless codes.is_a?(Array) && codes.size.between?(1, 16) && codes.uniq == codes
    invalid! unless @step_codes.select { |code| codes.include?(code) } == codes
  end

  def validate_adjacent!(left, right)
    raise JrcApprovals::Error, 'TIER_OVERLAP' if left.overlaps?(right)
    raise JrcApprovals::Error, 'TIER_GAP' if @tiers['coverage'] == 'complete' && left.gap?(right)
  end

  def validate_coverage!
    complete = @ranges.first.covers_min?(@domain.min) && @ranges.last.covers_max?(@domain.max)
    raise JrcApprovals::Error, 'TIER_GAP' unless complete
  end

  def invalid!
    raise JrcApprovals::Error, 'INVALID_TIER_DEFINITION'
  end
end
