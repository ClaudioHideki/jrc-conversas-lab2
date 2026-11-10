# Restoration is a new governed native version. Historic versions and every
# previously pinned review/configuration reference remain unchanged.
class JrcRelationship::ConfigurationRestore
  def initialize(context)
    @account_id = context.account.id
    @actor_id = context.user.id
  end

  def call(scope_key:, version:, source_version:, reason:, portfolio_revision: nil)
    unless scope_key.is_a?(String) && JrcRelationship::Configuration::SCOPE_PATTERN.match?(scope_key)
      raise ArgumentError,
            'Use a native configuration scope'
    end

    validate_input!(version, source_version, reason)
    JrcRelationship::DistributionConfigurationGovernance.synchronize(@account_id) do
      JrcRelationship::BatchReviewAuthority.new(account_id: @account_id, actor_id: @actor_id, write: false).call do |context|
        record = locked_configuration!(context, scope_key, version, portfolio_revision)
        source = record.versions.lock('FOR SHARE').find_by!(account_id: @account_id, version: source_version)
        restore!(record, source, context, reason)
        { scope_key: record.scope_key, version: record.version, restored_from_version: source.version }
          .merge(JrcRelationship::PortfolioGroupConfiguration.payload(context, record.scope_key))
      end
    end
  end

  private

  def locked_configuration!(context, scope, version, portfolio_revision)
    raise Pundit::NotAuthorizedError unless context.policy.configure?

    context.authorize_configuration_scope!(scope)
    JrcRelationship::PortfolioGroupConfiguration.verify_revision!(context, scope, portfolio_revision)
    record = JrcRelationship::Configuration.where(account_id: @account_id, scope_key: scope).lock('FOR UPDATE NOWAIT').first!
    raise ActiveRecord::StaleObjectError.new(record, 'restore') unless record.version == version

    record
  end

  def validate_input!(version, source, reason)
    raise ArgumentError, 'Use whole-number current and prior configuration versions' unless [version, source].all? do |value|
      value.is_a?(Integer) && value.positive?
    end
    raise ArgumentError, 'Choose a prior configuration version' unless source < version
    raise ArgumentError, 'Provide a bounded restoration reason' unless reason.is_a?(String) && reason.strip.length.between?(1, 4000)
  end

  def restore!(record, source, context, reason)
    previous = { 'version' => record.version, 'weights' => record.effective_weights, 'rules' => record.effective_rules }
    JrcRelationship::DistributionConfigurationGovernance.authorize!(account: context.account, user: context.user, configuration: record,
                                                                    rules: source.rules)
    local = source.rules[JrcRelationship::LocalAccess::KEY]
    if local && !JrcRelationship::LocalRoleRules.allowed?(local, user_id: context.user.id, action: 'configure', owner_id: :metadata)
      raise Pundit::NotAuthorizedError
    end
    record.assign_attributes(weights: source.weights.deep_dup, rules: source.rules.deep_dup, version: record.version + 1)
    record.save!
    JrcRelationship::DistributionConfigurationGovernance.record_versions!(record, actor: context.user, previous: previous)
    context.audit!(record, action: 'configuration_restored', before: { version: previous.fetch('version') },
                           after: { version: record.version, restored_from_version: source.version, reason: reason.strip })
  end
end
