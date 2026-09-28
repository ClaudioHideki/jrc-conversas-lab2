# frozen_string_literal: true

# Operational projection of native lookups; never grants UnitMembership administration.
class JrcServiceDesk::LookupPolicy < JrcServiceDesk::OperationalPolicy
  def index?
    any_unit_allowed? && capability?(:lookups_view)
  end
end
