# frozen_string_literal: true

# Eligibility metadata only, within the existing current HistoryContext. It
# neither creates consent nor changes ACW or enqueues work on a GET request.
class JrcContactCenter::EndingActions::ManualDestinationPreview
  REFUSALS = %w[ending_action_origin_unavailable ending_action_pending_permanently_blocked
                ending_action_destination_unavailable ending_action_trigger_pending
                ending_customer_reference_changed ending_customer_explicit_reference_required
                ending_action_source_scope_changed].freeze

  def initialize(account:, member:, origin:)
    @account = account
    @member = member
    @origin = origin
  end

  def call
    return [] unless @origin.account_id == @account.id && @origin.actor_account_user_id == @member.id &&
                     @origin.actor_user_id == @member.user_id

    JrcContactCenter::EndingActions::SourceAuthority.new(account: @account, member: @member).call(@origin)
    version = JrcContactCenter::EndingActionVersion.where(account: @account).find(@origin.version_id)
    document = JrcContactCenter::EndingActions::RuleDefinition.new.call(version.definition)
    document.fetch('entries').flat_map { |rule| rule_previews(rule) }
  rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
    []
  rescue JrcContactCenter::OperationError => e
    raise unless REFUSALS.include?(e.code)

    []
  end

  private

  def eligible_rule?(definition)
    definition['destination_schema_version'] == 2 && definition['execution_mode'] == 'agent_confirmation' &&
      definition.fetch('active') && definition.fetch('queue_id') == @origin.queue_id.to_s
  end

  def rule_previews(definition)
    return [] unless eligible_rule?(definition)

    code = definition.fetch('code')
    rule = JrcContactCenter::EndingActions::PinnedRule.new(account: @account, origin: @origin).call(code)
    ready = JrcContactCenter::EndingActions::ExecutionReadiness.new(account: @account, origin: @origin).call(code)
    return [] unless JrcContactCenter::EndingActions::NativeTrigger.new(origin: @origin).call(rule)

    rule.fetch('actions').filter_map { |action| preview(action, code, ready) }
  rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
    []
  rescue JrcContactCenter::OperationError => e
    raise unless REFUSALS.include?(e.code)

    []
  end

  def preview(action, code, readiness)
    kind = action.fetch('kind')
    recorded = JrcContactCenter::EndingDestinationAttempt.exists?(account: @account, origin: @origin, rule_code: code, destination_kind: kind)
    return if recorded

    JrcContactCenter::EndingActions::ConfiguredNativeAction.new(account: @account, member: @member).call(action, active: true)
    JrcContactCenter::EndingActions::OriginalCustomerReference.new(account: @account, member: @member, origin: @origin).call if kind == 'crm'
    input = ApplicationRecord.sanitize_sql_array([
      'SELECT cc_ending_destination_context(?, ?, ?, ?, ?)::text', @account.id, @origin.id, readiness.id, code, kind
    ])
    metadata = JSON.parse(ApplicationRecord.connection.select_value(input))
    metadata.slice('origin_id', 'readiness_id', 'version_id', 'rule_code', 'destination_kind', 'operation', 'rule_sha256')
            .transform_values(&:to_s)
  rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
    nil
  rescue JrcContactCenter::OperationError => e
    raise unless REFUSALS.include?(e.code)

    nil
  end
end
