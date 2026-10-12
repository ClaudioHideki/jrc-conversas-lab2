class JrcApprovals::Delegations
  def initialize(account:, user:)
    @account, @user = account, user
  end

  def create!(policy_version_id:, step_code:, principal_id:, delegate_id:, actions:, reason:, starts_at:, ends_at:)
    JrcApprovals::Delegation.transaction do
      version = JrcApprovals::PolicyVersion.where(account_id: @account.id).find(policy_version_id)
      company_id, unit_id = version.publication.values_at('issuer_company_id', 'business_unit_id')
      grantor = JrcApprovals::Authorization.new(account: @account, user: @user)
        .authorize!('policy_manage', company_id: company_id, unit_id: unit_id)
      step = version.definition['steps'].find { |item| item['code'] == step_code }
      raise JrcApprovals::Error, 'INVALID_DELEGATION' unless version.definition['delegation_allowed'] && step &&
        actions.is_a?(Array) && actions.any? && actions.uniq == actions && (actions - step['actions']).empty? &&
        reason.is_a?(String) && reason.strip.present? && starts_at < ends_at && ends_at > Time.current
      eligibility = JrcApprovals::Eligibility.new(account: @account, company_id: company_id, unit_id: unit_id)
      principal, delegate = @account.account_users.find(principal_id), @account.account_users.find(delegate_id)
      raise Pundit::NotAuthorizedError unless eligibility.candidates(step).include?(principal.id) && eligibility.capable?(delegate)

      grant = JrcApprovals::Delegation.create!(account: @account, policy_version: version, grantor: grantor, principal: principal,
        delegate: delegate, step_code: step_code, actions: actions, reason: reason.strip, starts_at: starts_at, ends_at: ends_at)
      JrcApprovals::Ledger.audit!(account: @account, actor: grantor, event: 'delegation_granted', key: "delegation:#{grant.id}:grant",
        data: { delegation_id: grant.id, principal_id: principal.id, delegate_id: delegate.id, reason: reason.strip }, policy_version_id: version.id)
      grant
    end
  end

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
