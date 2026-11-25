# frozen_string_literal: true

# Internal metadata admission only, without an HTTP actor or native effect.
# The persisted attempt owns delivery after commit when that increment is
# validated. Every unfinished delivery must separately enter
# ExecuteDestinationAttempt, which reauthorizes the original actor and target.
# Manual action consent is deliberately unavailable through this command.
class JrcContactCenter::EndingActions::QueueDestinationAttempt
  def initialize(account:, origin_id:, rule_code:, destination_kind:, request_key:)
    @account = account
    @origin_id = origin_id
    @code = rule_code
    @kind = destination_kind
    @key = request_key
  end

  def call
    context = JrcContactCenter::EndingActions::OriginalActorContext.new(account: @account, origin_id: @origin_id)
    context.call do |_member, origin|
      rule = JrcContactCenter::EndingActions::PinnedRule.new(account: @account, origin: origin).call(@code)
      validate_automatic_rule!(origin, rule)
      readiness = JrcContactCenter::EndingActions::ExecutionReadiness.new(account: @account, origin: origin).call(@code)
      JrcContactCenter::EndingActions::RecordDestinationAttempt.new(
        account: @account, origin: origin, readiness: readiness, rule_code: @code, destination_kind: @kind
      ).call(request_key: JrcServiceDesk::Input.request_key(@key))
    end
  end

  private

  def validate_automatic_rule!(origin, rule)
    raise JrcContactCenter::OperationError, 'ending_action_destination_unavailable' unless rule['destination_schema_version'] == 2
    raise JrcContactCenter::OperationError, 'ending_action_requires_agent_confirmation' unless rule.fetch('execution_mode') == 'automatic'

    configured = rule.fetch('actions').any? { |row| row.fetch('kind') == @kind }
    raise JrcContactCenter::OperationError, 'ending_action_destination_unavailable' unless configured

    trigger = JrcContactCenter::EndingActions::NativeTrigger.new(origin: origin).call(rule)
    raise JrcContactCenter::OperationError, 'ending_action_trigger_pending' unless trigger
  end
end
