require 'digest'

class JrcApprovals::Ledger
  def self.digest(value)
    JrcServiceDesk::CanonicalJson.digest(value)
  end

  # Transaction-scoped, deterministic locks plus database unique keys protect independent connections.
  def self.lock!(account_id, key)
    number = Digest::SHA256.hexdigest("jrc_approvals:#{account_id}:#{key}")[0, 16].to_i(16) - (1 << 63)
    ApplicationRecord.connection.execute("SELECT pg_advisory_xact_lock(#{number})")
  end

  def self.audit!(account:, actor:, event:, key:, data:, **references)
    JrcApprovals::AuditEvent.create!(references.merge(account: account, actor: actor, event_type: event,
                                                      correlation_key: key, data: JrcServiceDesk::CanonicalJson.normalize(data)))
  end

  def self.key!(key)
    raise JrcApprovals::Error, 'INVALID_IDEMPOTENCY_KEY' unless key.is_a?(String) && key.match?(/\A[a-zA-Z0-9_.:-]{1,128}\z/)

    key
  end

  def self.expected!(record, expected)
    raise JrcApprovals::Error, 'VERSION_CONFLICT' unless expected.is_a?(Integer) && record.lock_version == expected
  end
end
