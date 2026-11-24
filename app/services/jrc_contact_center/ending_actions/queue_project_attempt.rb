# frozen_string_literal: true

# Internal scheduling command. Persisting work never sends a message or creates
# a task. Both scheduling and execution use the attested original agent's
# current authority; an HTTP operator cannot supply another actor or template.
class JrcContactCenter::EndingActions::QueueProjectAttempt
  def initialize(account:, origin_id:, rule_code:, request_key:)
    @account = account
    @origin_id = origin_id
    @code = rule_code
    @request_key = request_key
  end

  def call
    context = JrcContactCenter::EndingActions::OriginalActorContext.new(account: @account, origin_id: @origin_id)
    context.call do |member, origin|
      rule = JrcContactCenter::EndingActions::PinnedRule.new(account: @account, origin: origin).call(@code)
      readiness = JrcContactCenter::EndingActions::ExecutionReadiness.new(account: @account, origin: origin).call(@code)
      validate_destination!(member, origin, rule)
      JrcContactCenter::EndingActions::RecordAttempt.new(account: @account, origin: origin, rule_code: @code,
                                                         readiness: readiness, request_key: @request_key).call
    end
  end

  private

  def validate_destination!(member, origin, rule)
    raise JrcContactCenter::OperationError, 'ending_action_requires_agent_confirmation' unless rule.fetch('execution_mode') == 'automatic'

    trigger = JrcContactCenter::EndingActions::NativeTrigger.new(origin: origin).call(rule)
    raise JrcContactCenter::OperationError, 'ending_action_trigger_pending' unless trigger

    action = rule.fetch('actions').find { |entry| entry.fetch('kind') == 'project_task' }
    raise JrcContactCenter::OperationError, 'ending_action_destination_unavailable' unless action

    JrcContactCenter::EndingActions::ProjectTaskParameters.new(member: member).call(action.fetch('parameters'))
  end
end
