# frozen_string_literal: true

# Compatibility endpoint: now governed by CP4-D01, not a policy bypass.
class JrcServiceDesk::ChangeWorkStatusService < JrcServiceDesk::BaseService
  def call(ticket_id:, status_id:, expected_lock_version:)
    with_ticket(ticket_id, :show?) do |ticket|
      Pundit.authorize(context.to_h, ticket, :change_work_status?, policy_class: JrcServiceDesk::WorkStatusPolicy)
      expected = JrcServiceDesk::Input.version(expected_lock_version)
      target = reference(JrcServiceDesk::TicketStatus, JrcServiceDesk::Input.id(status_id), ticket.unit)
      raise ArgumentError, 'Only configured working states here' unless target.phase == 'open' && ticket.status.phase == 'open'
      if target.id == ticket.status_id
        verify_version!(ticket, expected)
        next ticket
      end
      version = JrcServiceDesk::LifecycleSelector.new(ticket).applicable
      rules = version.definition['transitions'].select { |r| r['action'] == 'work_status' && r['from_status_ids'].include?(ticket.status_id) && r['to_status_id'] == target.id }
      raise ArgumentError, 'Use an explicit lifecycle rule' unless rules.length == 1
      JrcServiceDesk::LifecycleTransitionService.new(user_context: context.to_h).call(ticket_id: ticket.id,
        attributes: { rule_key: rules.first['key'], expected_lock_version: expected, expected_policy_version_id: version.id },
        idempotency_key: "work-status:#{ticket.id}:#{actor_membership.id}:#{expected}:#{target.id}")
      ticket.reload
    end
  end
end
