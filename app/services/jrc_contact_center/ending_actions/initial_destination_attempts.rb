# frozen_string_literal: true

# Trusted qualification-event admission, following the existing v1 producer.
# Only attested native origins, pinned rules and prospective readiness are used.
# Admission records technical work; the separate worker reauthorizes the current
# original agent for every native effect, including a refused pending attempt.
class JrcContactCenter::EndingActions::InitialDestinationAttempts
  def initialize(account:, qualification_id:)
    @account = account
    @qualification_id = qualification_id
  end

  def call
    origin = JrcContactCenter::EndingActionOrigin.find_by(account: @account, source_qualification_id: @qualification_id)
    return [] unless origin

    document = JrcContactCenter::EndingActions::RuleDefinition.new.call(origin.version.definition)
    rules = document.fetch('entries').select { |rule| automatic_rule?(rule, origin) }
    rules.flat_map do |rule|
      rule.fetch('actions').filter_map { |action| prepare_one(origin, rule.fetch('code'), action.fetch('kind')) }
    end
  end

  private

  def automatic_rule?(rule, origin)
    rule['destination_schema_version'] == 2 && rule.fetch('active') && rule['execution_mode'] == 'automatic' &&
      rule.fetch('queue_id') == origin.queue_id.to_s
  end

  def prepare_one(origin, code, kind)
    context = JrcContactCenter::EndingActions::OriginalActorContext.new(account: @account, origin_id: origin.id)
    row, created = context.call do |_member, current_origin|
      previous = JrcContactCenter::EndingDestinationAttempt.where(
        account: @account, origin: current_origin, rule_code: code, destination_kind: kind, retry_of_id: nil
      ).order(:id).first
      next [previous, false] if previous

      record_one(current_origin, code, kind)
    end
    JrcContactCenter::EndingActions::DispatchDestinationAttempt.call(row) if row && !created
    row
  rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
    nil
  rescue JrcContactCenter::OperationError => e
    expected = %w[ending_action_pending_permanently_blocked ending_action_origin_unavailable]
    raise unless expected.include?(e.code)

    nil
  end

  def record_one(origin, code, kind)
    rule = JrcContactCenter::EndingActions::PinnedRule.new(account: @account, origin: origin).call(code)
    readiness = JrcContactCenter::EndingActions::ExecutionReadiness.new(account: @account, origin: origin).call(code)
    return [nil, false] unless JrcContactCenter::EndingActions::NativeTrigger.new(origin: origin).call(rule)

    row = JrcContactCenter::EndingActions::RecordDestinationAttempt.new(
      account: @account, origin: origin, readiness: readiness, rule_code: code, destination_kind: kind
    ).call(request_key: SecureRandom.uuid)
    [row, true]
  end
end
