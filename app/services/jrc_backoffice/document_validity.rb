require 'date'

# Calendar validity is an explicit human decision, not an OCR inference.
# The decision captures its time zone; changing the account zone later cannot
# silently change the interpretation of its expiration date.
class JrcBackoffice::DocumentValidity
  UNSPECIFIED = Object.new.freeze

  def self.parse(value)
    return nil if value.nil?
    if value.instance_of?(Date)
      raise ArgumentError, 'Document validity is outside the supported calendar' unless value.year.between?(1, 9999)
      return value
    end

    raise ArgumentError, 'Document validity must be an ISO calendar date or null' unless
      value.is_a?(String) && value.match?(/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/)

    date = Date.iso8601(value)
    raise ArgumentError, 'Document validity is outside the supported calendar' unless date.year.between?(1, 9999)

    date
  rescue Date::Error
    raise ArgumentError, 'Document validity is not a real calendar date'
  end

  def self.resolve(value:, previous:)
    value.equal?(UNSPECIFIED) ? previous : parse(value)
  end

  def self.status(decision_status:, expires_on:, local_date:)
    return decision_status unless decision_status == 'approved'
    return decision_status if expires_on.nil?

    raise ArgumentError, 'A local calendar date is required' unless local_date.instance_of?(Date)

    parse(expires_on) < local_date ? 'expired' : 'approved'
  end

  def self.revision!(expected, actual, validity: UNSPECIFIED)
    if !validity.equal?(UNSPECIFIED) && expected.equal?(UNSPECIFIED)
      raise ArgumentError, 'A review revision is required when changing document validity'
    end
    return if expected.equal?(UNSPECIFIED)
    raise ArgumentError, 'Expected document decision must be a positive ID or null' unless
      expected.nil? || (expected.is_a?(Integer) && expected.positive?)
    raise JrcBackoffice::Documents::Conflict, 'Document review changed; reload before deciding' unless expected == actual
  end
end
