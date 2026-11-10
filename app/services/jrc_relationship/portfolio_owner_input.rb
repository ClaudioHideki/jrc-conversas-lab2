# Input shape only. Native account, destination and work permissions remain
# mandatory in the existing portfolio writers and reviewed plan.
class JrcRelationship::PortfolioOwnerInput
  def self.parse(value)
    return if value.nil? || value == ''

    valid = value.is_a?(Integer) || (value.is_a?(String) && value.match?(/\A[0-9]+\z/))
    raise ArgumentError, 'Use a scalar positive owner ID or nil to unassign' unless valid

    id = Integer(value.to_s, 10)
    raise ArgumentError, 'Use a scalar positive owner ID or nil to unassign' unless id.positive?

    id
  end
end
