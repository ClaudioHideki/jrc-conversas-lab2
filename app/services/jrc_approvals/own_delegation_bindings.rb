# Resolve a global own grant against one immutable native request, never a blanket role grant.
class JrcApprovals::OwnDelegationBindings
  def self.choices(account:, user:, record:, step:, principals:)
    new(account: account, user: user, record: record).choices(step: step, principals: principals)
  end

  def self.own_id(delegation)
    JrcApprovals::AuditEvent.find_by(account_id: delegation.account_id,
                                     correlation_key: "delegation:#{delegation.id}:grant")&.data&.fetch('own_delegation_id', nil)
  end

  def initialize(account:, user:, record:)
    @account = account
    @user = user
    @record = record
  end

  def choices(step:, principals:)
    return [] unless supported?

    JrcApprovals::OwnDelegations.grants(@account, delegate_id: actor.id).filter_map do |grant|
      next unless principals.include?(grant.principal_id)

      begin
        actions = permitted!(grant, step)
        next if actions.empty?

        principal = @account.account_users.includes(:user).find(grant.principal_id)
        { own_delegation_id: grant.id, delegation_id: nil, principal_name: principal.user.name, actions: actions }
      rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound, JrcApprovals::Error
        nil
      end
    end
  end

  def materialize!(id:, step_code:, decision:)
    grant = JrcApprovals::OwnDelegations.find!(@account, id)
    step = @record.policy_version.definition.fetch('steps').find { |row| row['code'] == step_code }
    actions = permitted!(grant, step)
    raise JrcApprovals::Error, 'INVALID_DELEGATION' unless actions.include?(decision)

    JrcApprovals::Ledger.lock!(@account.id, 'own-delegation-topology')
    raise JrcApprovals::Error, 'INVALID_DELEGATION' unless grant.active?

    correlation = "own_binding:#{grant.id}:#{@record.policy_version_id}:#{step_code}"
    audit = JrcApprovals::AuditEvent.find_by(account_id: @account.id, correlation_key: correlation)
    return JrcApprovals::Delegation.where(account_id: @account.id).find(audit.data.fetch('delegation_id')) if audit

    create_binding!(grant, step_code, actions, correlation)
  end

  def verify_scoped!(delegation, step, decision)
    id = self.class.own_id(delegation)
    return unless id

    actions = permitted!(JrcApprovals::OwnDelegations.find!(@account, id), step)
    raise JrcApprovals::Error, 'INVALID_DELEGATION' unless actions.include?(decision)
  end

  private

  def actor
    @actor ||= @account.account_users.find_by!(user_id: @user.id)
  end

  def supported?
    key = "#{@record.module_key}.#{@record.event_key}"
    @record.policy_version.definition['delegation_allowed'] && !JrcApprovals::GratuityCatalog.gratuity_key?(key)
  end

  def validate_grant!(grant)
    valid = supported? && grant.account_id == @account.id && @record.account_id == @account.id &&
            grant.active? && grant.delegate_id == actor.id && grant.covers?(@record.issuer_company_id, @record.business_unit_id)
    raise JrcApprovals::Error, 'INVALID_DELEGATION' unless valid
  end

  def permitted!(grant, step)
    validate_grant!(grant)
    raise JrcApprovals::Error, 'INVALID_DELEGATION' unless step

    principal = @account.account_users.find(grant.principal_id)
    JrcApprovals::Authorization.new(account: @account, user: principal.user)
                               .authorize!('delegate', company_id: grant.issuer_company_id, unit_id: grant.business_unit_id)
    validate_eligibility!(principal, step)
    grant.actions & step['actions']
  end

  def validate_eligibility!(principal, step)
    eligibility = JrcApprovals::Eligibility.new(account: @account, company_id: @record.issuer_company_id,
                                                unit_id: @record.business_unit_id, catalog_key: "#{@record.module_key}.#{@record.event_key}")
    plan = @record.stage_plan.find { |row| row['code'] == step['code'] }
    if plan && plan['principal_ids'].include?(principal.id) && eligibility.candidates(step).include?(principal.id) && eligibility.capable?(actor)
      return
    end

    raise Pundit::NotAuthorizedError
  end

  def create_binding!(grant, step, actions, correlation)
    principal = @account.account_users.find(grant.principal_id)
    recipient = @account.account_users.find(grant.delegate_id)
    delegation = JrcApprovals::Delegation.create!(account: @account, policy_version: @record.policy_version, grantor: principal,
                                                  principal: principal, delegate: recipient, step_code: step, actions: actions,
                                                  reason: grant.binding_reason,
                                                  starts_at: grant.starts_at, ends_at: grant.ends_at)
    JrcApprovals::Ledger.audit!(account: @account, actor: principal, event: 'own_delegation_bound', key: correlation,
                                data: { own_delegation_id: grant.id, delegation_id: delegation.id }, policy_version_id: @record.policy_version_id)
    JrcApprovals::Ledger.audit!(account: @account, actor: principal, event: 'delegation_granted', key: "delegation:#{delegation.id}:grant",
                                data: { own_delegation_id: grant.id, delegation_id: delegation.id,
                                        principal_id: principal.id, delegate_id: recipient.id },
                                policy_version_id: @record.policy_version_id)
    delegation
  end
end
