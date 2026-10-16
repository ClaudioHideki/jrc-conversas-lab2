class JrcApprovals::Delegations
  def initialize(account:, user:)
    @account = account
    @user = user
  end

  def create!(policy_version_id:, step_code:, principal_id:, delegate_id:, actions:, reason:, starts_at:, **formal_absence)
    raise ArgumentError, 'Unknown delegation fields' unless (formal_absence.keys - [:absence_authorization, :ends_at]).empty?

    ends_at = formal_absence.fetch(:ends_at)
    absence_authorization = formal_absence[:absence_authorization]
    JrcApprovals::Delegation.transaction do
      version, grantor, company_id, unit_id = delegation_context(policy_version_id)
      step = version.definition['steps'].find { |item| item['code'] == step_code }
      validate_terms!(version, step, actions, reason, [starts_at, ends_at])

      catalog_key = "#{version.policy.module_key}.#{version.policy.event_key}"
      eligibility = JrcApprovals::Eligibility.new(account: @account, company_id: company_id, unit_id: unit_id, catalog_key: catalog_key)
      principal = @account.account_users.find(principal_id)
      delegate = @account.account_users.find(delegate_id)
      raise Pundit::NotAuthorizedError unless eligibility.candidates(step).include?(principal.id) && eligibility.capable?(delegate)

      validate_formal_absence!(version, step_code, principal.id, delegate.id, absence_authorization)

      grant = JrcApprovals::Delegation.create!(account: @account, policy_version: version, grantor: grantor, principal: principal,
                                               delegate: delegate, step_code: step_code, actions: actions,
                                               reason: reason.strip, starts_at: starts_at, ends_at: ends_at)
      audit_grant!(grant, grantor, absence_authorization)
      grant
    end
  end

  def delegation_context(policy_version_id)
    version = JrcApprovals::PolicyVersion.where(account_id: @account.id).find(policy_version_id)
    company_id, unit_id = version.publication.values_at('issuer_company_id', 'business_unit_id')
    grantor = JrcApprovals::Authorization.new(account: @account, user: @user)
                                         .authorize!('policy_manage', company_id: company_id, unit_id: unit_id)
    [version, grantor, company_id, unit_id]
  end
  private :delegation_context

  def audit_grant!(grant, actor, absence)
    data = { delegation_id: grant.id, principal_id: grant.principal_id, delegate_id: grant.delegate_id, reason: grant.reason }
    data[:absence_authorization] = absence unless absence.nil?
    JrcApprovals::Ledger.audit!(account: @account, actor: actor, event: 'delegation_granted', key: "delegation:#{grant.id}:grant",
                                data: data, policy_version_id: grant.policy_version_id)
  end
  private :audit_grant!

  def validate_terms!(version, step, actions, reason, period)
    starts_at, ends_at = period
    valid = version.definition['delegation_allowed'] && step && valid_actions?(actions, step)
    valid &&= valid_period?(reason, starts_at, ends_at)
    raise JrcApprovals::Error, 'INVALID_DELEGATION' unless valid
  end

  def valid_period?(reason, starts_at, ends_at)
    reason.is_a?(String) && reason.strip.present? && starts_at < ends_at && ends_at > Time.current
  end

  def valid_actions?(actions, step)
    actions.is_a?(Array) && actions.any? && actions.uniq == actions && (actions - step['actions']).empty?
  end

  def validate_formal_absence!(version, step_code, principal_id, delegate_id, absence_authorization)
    catalog_key = "#{version.policy.module_key}.#{version.policy.event_key}"
    return unless JrcApprovals::GratuityCatalog.gratuity_key?(catalog_key)

    JrcApprovals::GratuityAuthorities.new(account: @account, company_id: version.publication['issuer_company_id']).validate_delegation!(
      step_code: step_code, principal_id: principal_id, delegate_id: delegate_id, absence_authorization: absence_authorization
    )
  end
  private :validate_terms!, :validate_formal_absence!, :valid_actions?, :valid_period?

  def revoke!(id:)
    JrcApprovals::Delegation.transaction do
      grant = JrcApprovals::Delegation.where(account_id: @account.id).lock.find(id)
      company_id, unit_id = grant.policy_version.publication.values_at('issuer_company_id', 'business_unit_id')
      actor = JrcApprovals::Authorization.new(account: @account, user: @user)
        .authorize!('policy_manage', company_id: company_id, unit_id: unit_id)
      next grant if grant.revoked_at

      grant.update!(revoked_at: Time.current)
      JrcApprovals::Ledger.audit!(account: @account, actor: actor, event: 'delegation_revoked', key: "delegation:#{grant.id}:revoke",
        data: { delegation_id: grant.id }, policy_version_id: grant.policy_version_id)
      grant
    end
  end
end
