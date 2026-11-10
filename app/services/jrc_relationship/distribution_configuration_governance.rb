class JrcRelationship::DistributionConfigurationGovernance
  def self.synchronize(account_id)
    JrcRelationship::Configuration.transaction do
      JrcRelationship::DistributionApproval.lock_configuration!(account_id)
      yield
    end
  end

  def self.authorize!(account:, user:, configuration:, rules:)
    current = configuration.effective_rules.fetch('portfolio_transfer_approval_required')
    return if current == rules.fetch('portfolio_transfer_approval_required', false)

    kind, id = configuration.scope_key.split(':')
    unit = account.jrc_crm_business_units.find(id) if kind == 'unit'
    unit = JrcRelationship::PortfolioGroup.where(account: account).find(id).business_unit if kind == 'portfolio'
    JrcApprovals::Authorization.new(account: account, user: user)
                               .authorize!('policy_manage', company_id: unit&.company_id, unit_id: unit&.id)
  end

  def self.record_versions!(record, actor:, previous:)
    current = { 'version' => record.version, 'weights' => record.effective_weights, 'rules' => record.effective_rules }
    record.capture_version!(previous, actor: actor)
    record.capture_version!(current, actor: actor)
    event = JrcCustomers::Audit.record!(account: record.account, actor: actor, resource: record, event_type: 'relationship_updated',
                                        from_value: previous, to_value: current, metadata: { action: 'configuration_versioned', scope_key: record.scope_key })
    JrcRelationship::PortfolioHistoryDetails.capture!(event, resource: record)
    event
  end
end
