# A global own grant is an append-only native ledger entry, not a rewrite of v1 scoped grants.
class JrcApprovals::OwnDelegation
  attr_reader :record

  delegate :id, :account_id, to: :record

  def initialize(record)
    @record = record
  end

  def principal_id
    record.actor_id
  end

  def delegate_id
    record.data.fetch('delegate_id')
  end

  def issuer_company_id
    record.data.fetch('issuer_company_id')
  end

  def business_unit_id
    record.data.fetch('business_unit_id')
  end

  def starts_at
    Time.iso8601(record.data.fetch('starts_at'))
  end

  def ends_at
    Time.iso8601(record.data.fetch('ends_at'))
  end

  def actions
    record.data.fetch('actions')
  end

  def binding_reason
    record.data['reason'].presence || "Own delegation ##{id}; no reason supplied"
  end

  def revoked?
    JrcApprovals::AuditEvent.exists?(account_id: account_id, event_type: 'own_delegation_revoked',
                                     correlation_key: "own_delegation:revoked:#{id}")
  end

  def active?
    !revoked? && starts_at <= Time.current && ends_at > Time.current
  end

  def covers?(company_id, unit_id)
    (issuer_company_id.nil? || issuer_company_id == company_id) && (business_unit_id.nil? || business_unit_id == unit_id)
  end
end
