# frozen_string_literal: true

# Read/admission checks only. Audit/configuration authority never substitutes for
# the original operating agent. The executor rechecks all authority independently.
class JrcContactCenter::EndingActions::PendingProjectAction
  UNAVAILABLE = %w[
    ending_attempt_no_longer_pending ending_action_requires_agent_confirmation
    ending_action_pending_permanently_blocked ending_action_origin_unavailable
    ending_action_trigger_pending ending_action_destination_unavailable invalid_ending_task_parameters
  ].freeze

  def initialize(account:, member:, attempt:)
    @account = account
    @member = member
    @attempt = attempt
  end

  def call
    origin = authorized_origin
    raise JrcContactCenter::OperationError.new('ending_attempt_no_longer_pending', status: :conflict) if @attempt.outcome
    raise JrcContactCenter::OperationError, 'ending_action_destination_unavailable' unless @attempt.destination_kind == 'project_task'

    validate_rule!(origin)
  end

  def available?
    call
    true
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    false
  rescue JrcContactCenter::OperationError => e
    raise unless UNAVAILABLE.include?(e.code)

    false
  end

  private

  def authorized_origin
    raise ActiveRecord::RecordNotFound unless @attempt.account_id == @account.id && @member.account_id == @account.id

    origin = JrcContactCenter::EndingActionOrigin.where(account: @account).find(@attempt.origin_id)
    context = { account: @account, account_user: @member, user: @member.user }
    raise Pundit::NotAuthorizedError unless origin.actor_account_user_id == @member.id
    raise Pundit::NotAuthorizedError unless origin.actor_user_id == @member.user_id
    raise Pundit::NotAuthorizedError unless JrcContactCenter::ModulePolicy.new(context, :contact_center).operate?

    origin
  end

  def validate_rule!(origin)
    rule = JrcContactCenter::EndingActions::PinnedRule.new(account: @account, origin: origin).call(@attempt.rule_code)
    raise JrcContactCenter::OperationError, 'ending_action_requires_agent_confirmation' unless rule.fetch('execution_mode') == 'automatic'

    JrcContactCenter::EndingActions::ExecutionReadiness.new(account: @account, origin: origin).call(@attempt.rule_code)
    unless JrcContactCenter::EndingActions::NativeTrigger.new(origin: origin).call(rule)
      raise JrcContactCenter::OperationError, 'ending_action_trigger_pending'
    end
    action = rule.fetch('actions').find { |entry| entry.fetch('kind') == 'project_task' }
    raise JrcContactCenter::OperationError, 'ending_action_destination_unavailable' unless action

    JrcContactCenter::EndingActions::ProjectTaskParameters.new(member: @member).call(action.fetch('parameters'))
  end
end
