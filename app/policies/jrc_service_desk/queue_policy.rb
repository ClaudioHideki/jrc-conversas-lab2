# frozen_string_literal: true

class JrcServiceDesk::QueuePolicy < JrcServiceDesk::ConfigurationPolicy
  def show?
    super && (!operational_context.supervision_access.restricted?(record.unit_id) ||
      operational_context.supervision_access.grants.any? { |grant| grant[:queue_id] == record.id && grant[:team_id] == record.team_id })
  end

  class Scope < JrcServiceDesk::ConfigurationPolicy::Scope
    def resolve
      records = super
      access = operational_context.supervision_access
      records.where.not(unit_id: access.restricted_units).or(records.where(id: access.grants.map { |grant| grant[:queue_id] }))
    end
  end
end
