# Capacity refusal must not lose an eligible native handoff. Keep the canonical
# assignment unassigned for supervised allocation; never select another owner.
class JrcRelationship::HandoffAllocation
  def self.call(account:, identity:, attributes:)
    JrcRelationship::Assignment.create_or_find_by!(identity.merge(account: account)) { |row| row.assign_attributes(attributes) }
  rescue ActiveRecord::RecordInvalid => e
    raise unless capacity_only?(e.record)

    JrcRelationship::Assignment.create_or_find_by!(identity.merge(account: account)) do |row|
      row.assign_attributes(attributes.except(:owner_id))
      row.settings = row.settings.merge('allocation_pending_reason' => 'capacity_unavailable')
    end
  end

  def self.capacity_only?(record)
    errors = record.errors.details.values.flatten
    errors.present? && errors.all? { |entry| JrcRelationship::DistributionCapacityGuard::CAPACITY_ERRORS.include?(entry[:error]) }
  end
  private_class_method :capacity_only?
end
