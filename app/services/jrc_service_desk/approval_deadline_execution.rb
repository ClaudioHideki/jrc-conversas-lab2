# frozen_string_literal: true

# One deadline escalation per approval. No repeated escalation loop or public send.
class JrcServiceDesk::ApprovalDeadlineExecution < JrcServiceDesk::BaseService
  def call(approval_id:)
    initial = fresh_context!
    candidate = JrcServiceDesk::TicketApprovalPolicy::Scope.new(initial.to_h, JrcServiceDesk::TicketApproval).resolve.find(approval_id)
    with_ticket(candidate.ticket_id, :show?) do |ticket|
      approval = ticket.ticket_approvals.lock.find(candidate.id)
      rule = approval.deadline_rule_version
      current = JrcServiceDesk::OperationalRuleVersion.current(account_id: ticket.account_id, unit_id: ticket.unit_id, kind: 'approval_deadline')
      next unless rule&.enabled? && current&.id == rule.id && approval.status == 'pending'
      raise JrcServiceDesk::IdempotencyConflict unless rule.digest == rule.expected_digest

      values = rule.definition
      raise Pundit::NotAuthorizedError unless values.fetch('executor_account_user_id') == context.account_user.id
      next if Time.current < approval.due_at + values.fetch('after_due_seconds')

      key = "approval:#{approval.id}:deadline"
      prior = JrcServiceDesk::RuleExecution.find_by(account_id: ticket.account_id, unit_id: ticket.unit_id, operation_key: key)
      next prior if prior

      attributes = values.fetch('target').merge('reason' => values.fetch('reason'),
                                                'due_at' => (Time.current + values.fetch('new_due_seconds')).iso8601(6))
      result = JrcServiceDesk::EscalateApprovalService.new(user_context: context.to_h).call(
        ticket_id: ticket.id, approval_id: approval.id, attributes: attributes, expected_lock_version: approval.lock_version
      )
      JrcServiceDesk::RuleExecution.create!(account: ticket.account, unit: ticket.unit, ticket: ticket, rule_version: rule,
                                            operation_key: key, result: { 'approval_id' => result.id, 'history_index' => result.history.size - 1 })
    end
  end
end
