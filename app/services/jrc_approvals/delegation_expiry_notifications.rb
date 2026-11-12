# Expiry is already enforced by native decision-time checks. This only records its notification event once.
class JrcApprovals::DelegationExpiryNotifications
  def self.call
    emitted = JrcApprovals::NotificationOutbox.select(:source_event_id)
    JrcApprovals::AuditEvent.where(event_type: JrcApprovals::OwnDelegations::EVENT, id: emitted).find_each do |event|
      grant = JrcApprovals::OwnDelegation.new(event)
      next if grant.ends_at > Time.current || grant.revoked?

      emit!(event.account, event.actor, 'own_delegation_expired', "own_delegation:expired:#{grant.id}", grant_id: grant.id)
    end
    scoped_expiries!(emitted)
  end

  def self.scoped_expiries!(emitted)
    JrcApprovals::Delegation.where(revoked_at: nil).where('ends_at <= ?', Time.current).find_each do |grant|
      next if JrcApprovals::OwnDelegationBindings.own_id(grant)
      next unless JrcApprovals::AuditEvent.exists?(account_id: grant.account_id, id: emitted,
                                                   correlation_key: "delegation:#{grant.id}:grant")

      emit!(grant.account, grant.grantor, 'delegation_expired', "delegation:#{grant.id}:expired", delegation_id: grant.id)
    end
  end

  def self.emit!(account, actor, event, key, **data)
    return unless account.active? && account.feature_enabled?('jrc_approvals')

    JrcApprovals::AuditEvent.transaction do
      JrcApprovals::Ledger.lock!(account.id, key)
      unless JrcApprovals::AuditEvent.exists?(account_id: account.id, correlation_key: key)
        JrcApprovals::Ledger.audit!(account: account, actor: actor, event: event, key: key, data: data.merge(system_expiry: true))
      end
    end
  end
  private_class_method :emit!, :scoped_expiries!
end
