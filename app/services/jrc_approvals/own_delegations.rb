class JrcApprovals::OwnDelegations
  EVENT = 'own_delegation_granted'.freeze
  FIELDS = %i[delegate_id issuer_company_id business_unit_id actions reason starts_at ends_at idempotency_key].freeze

  def self.grants(account, delegate_id: nil)
    rows = JrcApprovals::AuditEvent.where(account_id: account.id, event_type: EVENT)
    rows = rows.where("data ->> 'delegate_id' = ?", delegate_id.to_s) if delegate_id
    rows.order(:id).map { |row| JrcApprovals::OwnDelegation.new(row) }
  end

  def self.find!(account, id)
    JrcApprovals::OwnDelegation.new(JrcApprovals::AuditEvent.where(account_id: account.id, event_type: EVENT).find(id))
  end

  def self.check_scoped_topology!(account, principal_id, delegate_id, period)
    grants = grants(account).reject(&:revoked?)
    return if grants.empty?

    links = grants.map { |grant| [grant.principal_id, grant.delegate_id, grant.starts_at, grant.ends_at] }
    links.concat(JrcApprovals::Delegation.where(account_id: account.id, revoked_at: nil)
                                       .pluck(:principal_id, :delegate_id, :starts_at, :ends_at))
    return unless JrcApprovals::DelegationTopology.new(links.group_by(&:first)).reaches?(delegate_id, principal_id, period)

    raise JrcApprovals::Error, 'INVALID_DELEGATION'
  end

  def initialize(account:, user:)
    @account = account
    @user = user
    @authorization = JrcApprovals::Authorization.new(account: account, user: user)
  end

  def create!(**input)
    input = input.reverse_merge(reason: nil)
    validate!(input)
    JrcApprovals::AuditEvent.transaction do
      actor = parties!(input)
      JrcApprovals::Ledger.lock!(@account.id, 'own-delegation-topology')
      correlation = "own_delegation:grant:#{actor.id}:#{input.fetch(:idempotency_key)}"
      data = grant_data(input)
      existing = JrcApprovals::AuditEvent.find_by(account_id: @account.id, correlation_key: correlation)
      if existing
        raise JrcApprovals::Error, 'IDEMPOTENCY_CONTENT_CONFLICT' unless existing.event_type == EVENT && existing.data == data

        next JrcApprovals::OwnDelegation.new(existing)
      end
      check_topology!(actor.id, input)
      audit = JrcApprovals::Ledger.audit!(account: @account, actor: actor, event: EVENT, key: correlation, data: data)
      JrcApprovals::OwnDelegation.new(audit)
    end
  end

  def revoke!(id:)
    JrcApprovals::AuditEvent.transaction do
      grant = self.class.find!(@account, id)
      actor = authorize_revoke!(grant)

      JrcApprovals::Ledger.lock!(@account.id, 'own-delegation-topology')
      unless grant.revoked?
        JrcApprovals::Ledger.audit!(account: @account, actor: actor, event: 'own_delegation_revoked',
                                    key: "own_delegation:revoked:#{grant.id}", data: { grant_id: grant.id, delegate_id: grant.delegate_id })
      end
      grant
    end
  end

  def authorize_revoke!(grant)
    raise Pundit::NotAuthorizedError unless grant.account_id == @account.id

    actor = @authorization.member!
    if actor.id == grant.principal_id
      begin
        return @authorization.authorize!('delegate', company_id: grant.issuer_company_id, unit_id: grant.business_unit_id)
      rescue Pundit::NotAuthorizedError
        # A separately authorized rule administrator can still revoke after own-delegation permission is removed.
      end
    end
    @authorization.authorize!('policy_manage', company_id: grant.issuer_company_id, unit_id: grant.business_unit_id)
  end

  private

  def validate!(input)
    raise JrcApprovals::Error, 'INVALID_INPUT' unless input.keys.sort == FIELDS.sort

    JrcApprovals::Ledger.key!(input[:idempotency_key])
    validate_references!(input)
    raise JrcApprovals::Error, 'INVALID_DELEGATION' unless valid_period?(input) && valid_actions?(input[:actions])

    reason = input[:reason]
    raise JrcApprovals::Error, 'INVALID_INPUT' unless reason.nil? || (reason.is_a?(String) && reason.bytesize <= 4096)
  end

  def valid_period?(input)
    period = input.values_at(:starts_at, :ends_at)
    period.all? { |value| value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone) } &&
      period.first < period.last && period.last > Time.current
  end

  def valid_actions?(actions)
    actions.is_a?(Array) && actions.any? && actions.uniq == actions && (actions - JrcApprovals::Definition::ACTIONS).empty?
  end

  def validate_references!(input)
    references = input.values_at(:issuer_company_id, :business_unit_id).compact
    valid = input[:delegate_id].is_a?(Integer) && input[:delegate_id].positive? &&
            references.all? { |id| id.is_a?(Integer) && id.positive? }
    raise JrcApprovals::Error, 'INVALID_SCOPE' unless valid
  end

  def parties!(input)
    company_id, unit_id = input.values_at(:issuer_company_id, :business_unit_id)
    actor = @authorization.authorize!('delegate', company_id: company_id, unit_id: unit_id)
    @authorization.authorize!('decide', company_id: company_id, unit_id: unit_id)
    recipient = @account.account_users.find(input.fetch(:delegate_id))
    JrcApprovals::Authorization.new(account: @account, user: recipient.user).authorize!('decide', company_id: company_id, unit_id: unit_id)
    actor
  end

  def grant_data(input)
    input.except(:idempotency_key).merge(reason: input[:reason].to_s.strip.presence,
                                         starts_at: input[:starts_at].getutc.iso8601(6), ends_at: input[:ends_at].getutc.iso8601(6)).stringify_keys
  end

  def check_topology!(principal_id, input)
    period = input.values_at(:starts_at, :ends_at)
    grants = self.class.grants(@account).reject(&:revoked?)
    links = grants.map { |grant| [grant.principal_id, grant.delegate_id, grant.starts_at, grant.ends_at] }
    links.concat(JrcApprovals::Delegation.where(account_id: @account.id, revoked_at: nil)
                                       .pluck(:principal_id, :delegate_id, :starts_at, :ends_at))
    raise JrcApprovals::Error, 'INVALID_DELEGATION' if principal_id == input[:delegate_id] ||
                                                       JrcApprovals::DelegationTopology.new(links.group_by(&:first)).reaches?(input[:delegate_id],
                                                                                                                              principal_id, period)
  end
end
