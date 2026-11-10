class JrcRelationship::PortfolioGroupCustomerInput
  def self.parse(ids)
    raise ArgumentError, 'Choose1to50 existing customer allocations' unless ids.is_a?(Array) && ids.size.between?(1, 50)

    values = ids.map { |id| JrcRelationship::PortfolioOwnerInput.parse(id) }
    raise ArgumentError, 'Choose unique positive allocation IDs' if values.any?(&:nil?) || values.uniq.size != values.size

    values.sort
  end
end
