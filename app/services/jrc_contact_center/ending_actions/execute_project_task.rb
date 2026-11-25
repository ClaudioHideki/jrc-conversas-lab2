# frozen_string_literal: true

# Internal native worker command; no HTTP input can replace its original actor.
# Each destination must retain its own outer original-actor transaction. A
# success receipt and the actual native Task/Audit commit in the same savepoint.
class JrcContactCenter::EndingActions::ExecuteProjectTask
  def initialize(account:, origin_id:, rule_code:)
    @account = account
    @origin_id = origin_id
    @rule_code = rule_code
  end

  def call(&attempt_wrapper)
    context = JrcContactCenter::EndingActions::OriginalActorContext.new(account: @account, origin_id: @origin_id)
    context.call do |member, origin|
      rule = JrcContactCenter::EndingActions::PinnedRule.new(account: @account, origin: origin).call(@rule_code)
      raise JrcContactCenter::OperationError, 'ending_action_destination_unavailable' if rule.key?('destination_schema_version')

      readiness = JrcContactCenter::EndingActions::ExecutionReadiness.new(account: @account, origin: origin).call(@rule_code)
      action = rule.fetch('actions').find { |entry| entry.fetch('kind') == 'project_task' }
      raise JrcContactCenter::OperationError, 'ending_action_destination_unavailable' unless action

      observe_execution!(attempt_wrapper, origin, readiness) do
        execute_or_replay!(member, origin, rule, readiness, action.fetch('parameters'))
      end
    end
  end

  private

  # Internal Ruby callback only. No endpoint/job passes user-supplied code.
  # A durable attempt writer can wrap the real effect inside the same original
  # actor transaction; the default call remains unchanged and independent.
  def observe_execution!(wrapper, origin, readiness, &)
    return yield unless wrapper

    metadata = { account_id: origin.account_id, origin_id: origin.id, version_id: origin.version_id,
                 actor_account_user_id: origin.actor_account_user_id, actor_user_id: origin.actor_user_id,
                 readiness_id: readiness.id, rule_code: @rule_code.dup.freeze, destination_kind: 'project_task' }.freeze
    wrapper.call(metadata, &)
  end

  def execute_or_replay!(member, origin, rule, readiness, parameters)
    # An earlier receipt never becomes a substitute for current destination
    # authority. Closed/deleted targets are history, not a reason to recreate.
    JrcContactCenter::EndingActions::ProjectTaskParameters.new(member: member).authorize_reference!(parameters)
    scope = JrcContactCenter::EndingActionExecution.where(account: @account, origin: origin, rule_code: @rule_code,
                                                          destination_kind: 'project_task')
    previous = scope.first
    previous || create_effect!(scope, member, readiness, parameters, trigger!(origin, rule))
  end

  def trigger!(origin, rule)
    raise JrcContactCenter::OperationError, 'ending_action_requires_agent_confirmation' unless rule.fetch('execution_mode') == 'automatic'

    trigger = JrcContactCenter::EndingActions::NativeTrigger.new(origin: origin).call(rule)
    raise JrcContactCenter::OperationError, 'ending_action_trigger_pending' unless trigger

    trigger
  end

  def create_effect!(scope, member, readiness, parameters, trigger)
    ApplicationRecord.transaction(requires_new: true) do
      key = SecureRandom.uuid
      task = JrcContactCenter::EndingActions::ProjectTaskDestination.new(account: @account, member: member).call(
        parameters: parameters, trigger_at: trigger.fetch(:at), timezone: readiness.source_timezone, correlation_id: key
      )
      # Actor/version/trigger/time/digest are derived by the owned database guard,
      # never accepted from a caller or reconstructed from the mutable editor.
      scope.create!(readiness: readiness, target_id: task.id, request_key: key).reload
    end
  end
end
