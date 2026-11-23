# frozen_string_literal: true

# Historical selection, not activation or authority. A worker must separately
# prove readiness for this exact version, reauthorize the actor and obtain a trigger.
class JrcContactCenter::EndingActions::PinnedRule
  def initialize(account:, origin:)
    @account = account
    @origin = JrcContactCenter::EndingActionOrigin.where(account: account).find(origin.id)
  end

  def call(code)
    version = JrcContactCenter::EndingActionVersion.where(account: @account).find(@origin.version_id)
    document = JrcContactCenter::EndingActions::RuleDefinition.new.call(version.definition)
    rule = document.fetch('entries').find { |entry| entry.fetch('code') == code }
    validate_rule!(rule)
    barrier = JrcContactCenter::EndingActions::BlockingRevision.new(account: @account, version_id: version.id, rule_code: code).call
    raise JrcContactCenter::OperationError, 'ending_action_pending_permanently_blocked' if barrier

    rule.deep_dup
  end

  private

  def validate_rule!(rule)
    available = rule && rule.fetch('active') && rule['execution_mode'].present? && rule.fetch('queue_id') == @origin.queue_id.to_s
    raise JrcContactCenter::OperationError, 'ending_action_origin_unavailable' unless available

    scope = rule.fetch('scope')
    expected = { 'queue_scope_version_id' => @origin.queue_scope_version_id.to_s,
                 'integrity_sha256' => @origin.queue_scope_version.integrity_sha256,
                 'unit_id' => @origin.unit_id.to_s, 'issuer_company_id' => @origin.issuer_company_id&.to_s,
                 'business_unit_id' => @origin.business_unit_id&.to_s }
    raise JrcContactCenter::OperationError, 'ending_action_origin_unavailable' unless scope == expected
  end
end
