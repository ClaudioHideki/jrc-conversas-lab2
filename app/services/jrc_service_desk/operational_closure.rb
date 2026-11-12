# frozen_string_literal: true

# Common native operators close visible tickets with a reason. This adapts only
# the input/role requirements; status edges, approvals, clocks and pinned SLA
# definitions still run through the existing lifecycle command.
class JrcServiceDesk::OperationalClosure
  def self.allowed?(context, ticket)
    context = JrcServiceDesk::OperationalContext.new(context) if context.is_a?(Hash)
    !context.employee_portal? && !context.customer_execution? && context.operational_unit_allowed?(ticket.unit) &&
      context.capability?(:close) && JrcServiceDesk::TicketPolicy.new(context.to_h, ticket).show?
  end

  def self.prepare(rule, payload, context, ticket, automated: false)
    return rule if automated || (rule['action'] != 'close' && !payload.key?('closing_reason'))
    return rule unless allowed?(context, ticket)

    raise ArgumentError, 'A closing reason is required' if rule['action'] == 'close' && !payload.key?('closing_reason')

    self.rule(rule, context, ticket)
  end

  def self.rule(rule, context, ticket)
    return rule unless %w[resolve close].include?(rule['action']) && allowed?(context, ticket)

    fields = rule.dig('requirements', 'fields').slice('closing_reason').transform_values { |value| value.merge('required' => false) }
    requirements = { 'note' => false, 'solution' => false, 'classification' => false, 'evidence' => false, 'fields' => fields }
    rule.except('allowed_account_roles').merge('requirements' => requirements)
  end
end
