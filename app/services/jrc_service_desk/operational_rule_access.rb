# frozen_string_literal: true

# Native capabilities, never a second RBAC or administrator fallback.
class JrcServiceDesk::OperationalRuleAccess
  REQUIRED = {
    'routing' => %i[queues_manage], 'priority_matrix' => %i[priorities_manage],
    'sla_selection' => %i[lifecycle_policies_manage sla_snapshots_record contract_conditions_view],
    'approval_deadline' => %i[lifecycle_policies_manage approvals_request],
    'recurrence' => %i[incidents_manage]
  }.freeze

  def self.allowed?(context, kind)
    context.native_operator? && context.capability?(:settings_view) && REQUIRED.fetch(kind, []).any? &&
      REQUIRED.fetch(kind).all? { |capability| context.capability?(capability) }
  end

  def self.require!(context, kind, unit)
    raise Pundit::NotAuthorizedError unless allowed?(context, kind) && context.unit_allowed?(unit)
  end
end
