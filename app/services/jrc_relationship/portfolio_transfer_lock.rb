# An explicit portfolio restriction, independent from user removal or work completion.
class JrcRelationship::PortfolioTransferLock
  KEY = 'transfer_lock'.freeze

  def self.locked?(settings)
    return false unless settings.is_a?(Hash) && settings.key?(KEY)

    value = settings[KEY]
    return true unless value.is_a?(Hash) && [true, false].include?(value['locked'])

    value['locked']
  end

  def self.check!(record, owner_id:)
    return if record.owner_id.to_s == owner_id.to_s || !locked?(record.settings)

    raise ArgumentError, 'This portfolio owner transfer is explicitly locked'
  end

  # DistributionCapacityGuard already holds the native account configuration lock.
  # Read the persisted policy so an older ORM instance cannot bypass a newer hold.
  def self.validate_owner!(record)
    return unless record.persisted? && record.will_save_change_to_owner_id?

    stored = record.class.where(account_id: record.account_id, id: record.id).pick(:settings)
    projected_lock = record.will_save_change_to_settings? && locked?(record.settings)
    record.errors.add(:owner, 'transfer is explicitly locked') if locked?(stored) || projected_lock
  end

  def initialize(context)
    @context = context
  end

  def update!(id:, locked:, reason:, expected_version:)
    raise ArgumentError, 'Use an explicit boolean restriction' unless [true, false].include?(locked)
    raise ArgumentError, 'Provide a bounded justification' unless reason.is_a?(String) && reason.strip.length.between?(1, 4000)

    JrcRelationship::Assignment.transaction do
      authority.call do |context|
        raise Pundit::NotAuthorizedError unless context.policy.configure? && context.policy.team?

        record = context.assignment(id, write: true)
        record.with_lock { persist!(context, record, locked, reason.strip, expected_version) }
        record
      end
    end
  end

  private

  def authority
    JrcRelationship::BatchReviewAuthority.new(account_id: @context.account.id, actor_id: @context.user.id)
  end

  def persist!(context, record, locked, reason, expected_version)
    unless expected_version.is_a?(String) && expected_version == record.updated_at.utc.iso8601(6)
      raise ActiveRecord::StaleObjectError.new(record, 'update')
    end

    before = record.settings[KEY]
    return if before.is_a?(Hash) && before['locked'] == locked && before['reason'] == reason

    value = receipt(before, context.user.id, locked, reason)
    record.update!(settings: record.settings.merge(KEY => value))
    context.audit!(record, before: { KEY => before }, after: { KEY => value }, action: 'transfer_lock_changed')
  end

  def receipt(before, actor_id, locked, reason)
    previous = before.is_a?(Hash) && before['version'].is_a?(Integer) ? before['version'] : 0
    { 'version' => [previous, 0].max + 1, 'locked' => locked, 'reason' => reason,
      'actor_id' => actor_id, 'changed_at' => Time.current.utc.iso8601(6) }
  end
end
