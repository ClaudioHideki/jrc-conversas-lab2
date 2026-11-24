# frozen_string_literal: true

# Trusted native-event metadata preparation, never an HTTP grant. It may record
# work for an agent whose access was revoked so execution can retain a refused
# outcome. Only ExecuteAttempt can perform the effect, under current original
# source/destination authority. No template or actor comes from request input.
class JrcContactCenter::EndingActions::InitialProjectAttempts
  def initialize(account:, qualification_id:)
    @account = account
    @qualification_id = qualification_id
  end

  def call
    origin = JrcContactCenter::EndingActionOrigin.find_by(account: @account, source_qualification_id: @qualification_id)
    return [] unless origin

    document = JrcContactCenter::EndingActions::RuleDefinition.new.call(origin.version.definition)
    rules = document.fetch('entries').select do |rule|
      rule.fetch('active') && rule['execution_mode'] == 'automatic' && rule.fetch('queue_id') == origin.queue_id.to_s &&
        rule.fetch('actions').any? { |entry| entry.fetch('kind') == 'project_task' }
    end
    rules.filter_map { |rule| prepare_one(origin, rule.fetch('code')) }
  end

  private

  def prepare_one(origin, code)
    JrcContactCenter::EndingActions::ExecutionTransaction.call(account: @account) do
      previous = JrcContactCenter::EndingActionAttempt.where(account: @account, origin: origin, rule_code: code,
                                                            destination_kind: 'project_task').order(:id).first
      next previous if previous

      rule = JrcContactCenter::EndingActions::PinnedRule.new(account: @account, origin: origin).call(code)
      readiness = JrcContactCenter::EndingActions::ExecutionReadiness.new(account: @account, origin: origin).call(code)
      next unless JrcContactCenter::EndingActions::NativeTrigger.new(origin: origin).call(rule)

      JrcContactCenter::EndingActions::RecordAttempt.new(account: @account, origin: origin, rule_code: code,
                                                         readiness: readiness, request_key: SecureRandom.uuid).call
    end
  rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
    nil
  rescue JrcContactCenter::OperationError => error
    expected = %w[ending_action_pending_permanently_blocked ending_action_origin_unavailable]
    raise unless expected.include?(error.code)

    nil
  end
end
