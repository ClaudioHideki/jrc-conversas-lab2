# frozen_string_literal: true

class JrcServiceDesk::ApprovalDeadlineJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    JrcServiceDesk::TicketApproval.pending.where.not(deadline_rule_version_id: nil).where('due_at <= ?', Time.current)
                                  .where('NOT EXISTS (SELECT 1 FROM jrc_service_desk_rule_executions e WHERE ' \
                                         'e.account_id = jrc_service_desk_ticket_approvals.account_id AND ' \
                                         'e.unit_id = jrc_service_desk_ticket_approvals.unit_id AND ' \
                                         "e.operation_key = 'approval:' || jrc_service_desk_ticket_approvals.id::text || ':deadline')")
                                  .find_each(batch_size: 100) { |approval| process(approval) }
  end

  private

  def process(approval)
    rule = approval.deadline_rule_version
    return unless rule&.enabled?

    actor = AccountUser.where(account_id: approval.account_id).find(rule.definition.fetch('executor_account_user_id'))
    context = { account: approval.account, user: actor.user, account_user: actor }
    JrcServiceDesk::NativeExecutionContext.with(context) do
      JrcServiceDesk::ApprovalDeadlineExecution.new(user_context: context).call(approval_id: approval.id)
    end
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid,
         ActiveRecord::StaleObjectError, JrcServiceDesk::IdempotencyConflict, ArgumentError, KeyError
    # No exception/payload/customer text leaks; failures remain visible to operators.
    Rails.logger.info('JrcServiceDesk approval deadline blocked: authorization, configuration or concurrent change')
  end
end
