# frozen_string_literal: true

class JrcServiceDesk::PortalRoutingConfiguration
  KEY = 'jrc_service_desk_portal'
  FIELDS = %w[queue_id assignee_account_user_id stores_enabled].freeze

  def self.read(unit)
    unit.account.internal_attributes.fetch(KEY, {}).fetch(unit.id.to_s, {})
  end

  def self.revision(unit)
    JrcServiceDesk::CanonicalJson.digest(read(unit))
  end

  def self.resolve(unit:, context:, values: read(unit))
    return {} unless values['queue_id']
    raise Pundit::NotAuthorizedError unless context.capability?(:tickets_assign)

    queue = JrcServiceDesk::Queue.where(account_id: unit.account_id, unit_id: unit.id, active: true).find(values.fetch('queue_id'))
    result = { 'queue_id' => queue.id }
    return result unless values['assignee_account_user_id']

    member = JrcServiceDesk::UnitMembership.operational.where(account_id: unit.account_id, unit_id: unit.id, active: true,
                                                             manual_assignment_enabled: true).find_by!(account_user_id: values['assignee_account_user_id'])
    candidate = JrcServiceDesk::Ticket.new(account: unit.account, unit: unit, queue: queue, team_id: queue.team_id)
    raise Pundit::NotAuthorizedError unless JrcServiceDesk::AssignmentEligibility.manual_domain?(member, candidate)

    result.merge('assignee_account_user_id' => member.account_user_id)
  end

  def self.save!(unit:, actor:, values:, expected_revision:)
    context = JrcServiceDesk::OperationalContext.new(account: unit.account, user: actor.user, account_user: actor)
    raise Pundit::NotAuthorizedError unless context.administrator? && context.view_unit_scope.exists?(id: unit.id)
    raise ArgumentError, 'Invalid portal configuration' unless values.is_a?(Hash) && (values.keys - FIELDS).empty?

    values = values.compact
    if values['stores_enabled'] == true && !unit.account.feature_enabled?('jrc_customer_master')
      raise ArgumentError, 'Customer Master must be enabled for store selection'
    end
    raise ArgumentError, 'Invalid store selection' if values.key?('stores_enabled') && ![true, false].include?(values['stores_enabled'])
    %w[queue_id assignee_account_user_id].each { |key| values[key] = JrcServiceDesk::Input.id(values[key]) if values[key] }
    raise ArgumentError, 'An assignee requires a queue' if values['assignee_account_user_id'] && !values['queue_id']

    unit.account.with_lock do
      raise JrcServiceDesk::IdempotencyConflict unless expected_revision == revision(unit)

      previous = read(unit)
      resolve(unit: unit, context: context, values: values)
      data = unit.account.internal_attributes
      unit.account.update!(internal_attributes: data.merge(KEY => data.fetch(KEY, {}).merge(unit.id.to_s => values)))
      Audited::Audit.create!(auditable: unit, associated: unit.account, user: actor.user, action: 'update',
                            audited_changes: { 'portal_configuration' => [previous, values] }, comment: 'requester_portal_routing')
    end
    values
  end
end
