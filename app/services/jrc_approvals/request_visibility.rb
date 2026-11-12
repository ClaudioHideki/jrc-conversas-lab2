class JrcApprovals::RequestVisibility
  def self.authorize!(account:, user:, record:)
    auth = JrcApprovals::Authorization.new(account: account, user: user)
    member = auth.member!
    raise Pundit::NotAuthorizedError unless record.account_id == account.id

    if member.id == record.requester_id
      return auth.authorize!('request_create', company_id: record.issuer_company_id, unit_id: record.business_unit_id)
    end
    begin
      return auth.authorize!('view_audit', company_id: record.issuer_company_id, unit_id: record.business_unit_id)
    rescue Pundit::NotAuthorizedError
      auth.authorize!('decide', company_id: record.issuer_company_id, unit_id: record.business_unit_id)
    end
    principals = record.stage_plan.flat_map { |step| step['principal_ids'] }
    delegated = JrcApprovals::Delegation.where(account_id: account.id, delegate_id: member.id,
      policy_version_id: record.policy_version_id, principal_id: principals, revoked_at: nil)
      .where('starts_at <= ? AND ends_at > ?', Time.current, Time.current).any? do |grant|
        !JrcApprovals::OwnDelegationBindings.own_id(grant)
      end
    return member if principals.include?(member.id) || delegated
    own = record.policy_version.definition.fetch('steps').any? do |step|
      JrcApprovals::OwnDelegationBindings.choices(account: account, user: user, record: record,
        step: step, principals: principals).any?
    end
    raise Pundit::NotAuthorizedError unless own

    member
  end
end
