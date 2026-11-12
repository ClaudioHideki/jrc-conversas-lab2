# Endpoints are parsed by the native typed Conditions validator before use.
class JrcApprovals::TierInterval
  attr_reader :min, :max, :min_inclusive, :max_inclusive

  def initialize(min, max, min_inclusive, max_inclusive)
    @min = min
    @max = max
    @min_inclusive = min_inclusive
    @max_inclusive = max_inclusive
  end

  def valid?
    finite_flags? && ordered?
  end

  def contains?(value)
    above_min?(value) && below_max?(value)
  end

  def covers?(other)
    (min.nil? || (other.min && other.min >= min)) && (max.nil? || (other.max && other.max <= max))
  end

  def overlaps?(other)
    return true if max.nil? || other.min.nil?

    max > other.min || (max == other.min && max_inclusive && other.min_inclusive)
  end

  def gap?(other)
    return false if max.nil? || other.min.nil?

    max < other.min || (max == other.min && !max_inclusive && !other.min_inclusive)
  end

  def covers_min?(value)
    min == value && (value.nil? || min_inclusive)
  end

  def covers_max?(value)
    max == value && (value.nil? || max_inclusive)
  end

  private

  def finite_flags?
    !(min.nil? && min_inclusive) && !(max.nil? && max_inclusive)
  end

  def ordered?
    return true if min.nil? || max.nil?

    min < max || (min == max && min_inclusive && max_inclusive)
  end

  def above_min?(value)
    return true if min.nil?

    min_inclusive ? value >= min : value > min
  end

  def below_max?(value)
    return true if max.nil?

    max_inclusive ? value <= max : value < max
  end
end
