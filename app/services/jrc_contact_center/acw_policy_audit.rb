# Only the effective local ACW fields enter the native, permission-scoped audit.
class JrcContactCenter::AcwPolicyAudit
  def self.capture(account)
    policy = JrcContactCenter::AcwPolicy.new(account: account).call
    attributes = { 'voice_required' => policy.fetch(:voice_required) }
    omitted = []
    policy.fetch(:limits).each do |key, value|
      value.is_a?(Integer) ? attributes[key] = value : omitted << key
    end
    rules = JrcContactCenter::AcwScopedRules.new(account: account).call
    attributes['voice_rules'] = rules if rules.any?
    bindings = JrcContactCenter::AcwFormBindingPolicy.new(account: account).call
    attributes['voice_form_bindings'] = bindings if bindings.any?
    reasons = JrcContactCenter::AcwEndingReasons.new(account: account).call
    attributes['voice_reason_catalog'] = reasons if reasons.fetch('version').positive?
    { 'attributes' => attributes, 'omitted_fields' => omitted }
  end

  def self.write!(account:, before:, after:)
    return if before == after

    Audited.audit_class.create!(
      auditable: account, associated: account, user: Current.user, action: 'update',
      comment: JrcContactCenter::ConfigurationAudit::ACW_COMMENT, audited_changes: {
        'attributes' => [before.fetch('attributes'), after.fetch('attributes')],
        'cc_scope' => { 'before' => { 'account_id' => account.id.to_s }, 'after' => { 'account_id' => account.id.to_s } },
        'omitted_fields' => (before.fetch('omitted_fields') + after.fetch('omitted_fields')).uniq,
        'schema_version' => 1
      }
    )
  end
end
