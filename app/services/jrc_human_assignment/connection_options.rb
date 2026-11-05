class JrcHumanAssignment::ConnectionOptions
  def self.merge(previous, options)
    retained = (previous || {}).slice('visibility', 'supervisor_ids', 'agent_limits', 'agent_schedules').symbolize_keys
    JrcHumanAssignment::Policy::CONNECTION_DEFAULTS.merge(retained).merge(options)
  end

  def self.snapshot(options, previous:, enabled:)
    now = Time.current.iso8601(6)
    since = enabled ? previous&.fetch('requests_since', nil) || previous&.fetch('effective_from', nil) || Time.at(0).utc.iso8601(6) : now
    options.stringify_keys.merge('effective_from' => now, 'requests_since' => since)
  end

  def self.validate!(options)
    raise ArgumentError unless %w[shared assigned_only].include?(options[:visibility])

    validate_ids!(options[:supervisor_ids])
    limits = options[:agent_limits]
    raise ArgumentError unless limits.is_a?(Hash) && limits.size <= 1000 && limits.all? { |id, limit| valid_limit?(id, limit) }

    JrcHumanAssignment::AgentSchedule.validate!(options[:agent_schedules])
    return unless options[:visibility] == 'assigned_only'

    raise ArgumentError unless options.values_at(:respect_availability, :capacity_enabled, :waiting_enabled).all? &&
                               options[:fallback] == 'waiting' && options[:mode] != 'direct'
  end

  def self.validate_ids!(ids)
    raise ArgumentError unless ids.is_a?(Array) && ids.size <= 1000
    raise ArgumentError unless ids.all? { |id| id.is_a?(Integer) && id.positive? } && ids.uniq == ids
  end

  def self.valid_limit?(id, limit)
    id.is_a?(String) && id.match?(/\A[1-9]\d*\z/) && limit.is_a?(Integer) && limit.between?(1, 100)
  end
  private_class_method :valid_limit?

  def self.validate_members!(account, inbox, options)
    ids = (options[:supervisor_ids] + options[:agent_limits].keys.map(&:to_i) + options[:agent_schedules].keys.map(&:to_i)).uniq
    members = account.account_users.where(user_id: inbox.members.where(id: ids).select(:id))
    raise ArgumentError unless members.count == ids.size

    members.where(user_id: options[:supervisor_ids]).find_each do |member|
      raise ArgumentError if member.custom_role_id && member.permissions.exclude?('conversation_manage')
    end
  end
end
