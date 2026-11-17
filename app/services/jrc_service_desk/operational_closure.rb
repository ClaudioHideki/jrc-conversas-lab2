# frozen_string_literal: true

# Native staff may explicitly finish a visible ticket without configuration or
# workflow prerequisites. The existing lifecycle command still records the real
# actor, timestamps, measured clocks, audit and idempotency.
class JrcServiceDesk::OperationalClosure
  def self.allowed?(context, ticket)
    context = JrcServiceDesk::OperationalContext.new(context) if context.is_a?(Hash)
    !context.employee_portal? && !context.customer_execution? && (context.administrator? || context.operational_unit_allowed?(ticket.unit)) &&
      JrcServiceDesk::TicketPolicy.new(context.to_h, ticket).show?
  end

  def self.prepare(rule, payload, context, ticket, automated: false)
    if payload['operational_closure'] == true
      raise Pundit::NotAuthorizedError unless !automated && allowed?(context, ticket) && %w[resolve close].include?(rule['action'])

      return self.rule(rule, context, ticket, unrestricted: true)
    end
    return rule if automated || (rule['action'] != 'close' && !payload.key?('closing_reason'))
    return rule unless allowed?(context, ticket)

    raise ArgumentError, 'A closing reason is required' if rule['action'] == 'close' && !payload.key?('closing_reason')

    self.rule(rule, context, ticket)
  end

  def self.rule(rule, context, ticket, unrestricted: false)
    return rule unless %w[resolve close].include?(rule['action']) && allowed?(context, ticket)

    fields = rule.dig('requirements', 'fields').slice('closing_reason').transform_values { |value| value.merge('required' => false) }
    requirements = { 'note' => false, 'solution' => false, 'classification' => false, 'evidence' => false, 'fields' => fields }
    if unrestricted
      requirements['fields'] = {}
      clocks = rule.fetch('clocks').to_h { |kind, _effect| [kind, kind == 'first_response' ? 'stop' : 'complete'] }
      return rule.except('allowed_account_roles').merge('requirements' => requirements, 'end_pause' => true, 'clocks' => clocks)
    end
    rule.except('allowed_account_roles').merge('requirements' => requirements)
  end
end
