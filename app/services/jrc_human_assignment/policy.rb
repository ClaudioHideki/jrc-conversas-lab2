class JrcHumanAssignment::Policy
  CONNECTION_DEFAULTS = { respect_availability: true, capacity_enabled: true, waiting_enabled: true,
                          schedule: 'always', fallback: 'waiting', fallback_team_id: nil }.freeze
  def self.for(account)
    value = account.custom_attributes['jrc_human_assignment'] || {}
    { enabled: value['enabled'] == true, max_open: value.fetch('max_open', 10), inbox_ids: value.fetch('inbox_ids', []),
      last_agent_id: value.fetch('last_agent_id', 0) }
  end

  def self.enabled?(account)
    self.for(account)[:enabled] || connections(account).values.any? { |value| value['enabled'] == true }
  end

  def self.enabled_for?(account, inbox_id)
    override = connection_for(account, inbox_id)
    return override['enabled'] == true if override

    policy = self.for(account)
    policy[:enabled] && policy[:inbox_ids].include?(inbox_id)
  end

  def self.connections(account)
    account.custom_attributes.dig('jrc_human_assignment', 'connections') || {}
  end

  def self.connection_for(account, inbox_id)
    connections(account)[inbox_id.to_s]
  end

  def self.effective(account, inbox_id)
    base = self.for(account)
    override = connection_for(account, inbox_id)
    override ? base.merge(override.symbolize_keys) : base
  end

  def self.enabled_inbox_ids(account)
    ids = self.for(account)[:enabled] ? self.for(account)[:inbox_ids] : []
    (ids + connections(account).keys.map(&:to_i)).uniq.select { |id| enabled_for?(account, id) }
  end

  def self.update_connection!(account, inbox:, actor:, **options)
    options = CONNECTION_DEFAULTS.merge(options)
    validate_connection_options!(options)
    account.with_lock do
      ids = (options[:team_ids] + [options[:fallback_team_id]].compact).uniq
      validate_connection_access!(account, inbox, actor, ids)
      raise ArgumentError if options[:schedule] == 'inbox' && !inbox.reload.working_hours_enabled?
      value = options.stringify_keys.merge('effective_from' => Time.current.iso8601(6))
      persist_connection!(account, inbox, actor, value)
    end
  end

  def self.validate_connection_options!(options)
    raise ArgumentError unless options.keys.sort == (%i[enabled max_open mode team_ids] + CONNECTION_DEFAULTS.keys).sort

    validate_limits!(options[:enabled], options[:max_open])
    validate_inbox_ids!(options[:team_ids])
    validate_connection_mode!(options[:mode], options[:enabled], options[:team_ids])
    raise ArgumentError unless %i[respect_availability capacity_enabled waiting_enabled].all? { |key| [true, false].include?(options[key]) }
    raise ArgumentError unless %w[always inbox].include?(options[:schedule]) && %w[waiting default_team unassigned].include?(options[:fallback])
    raise ArgumentError if options[:fallback] == 'waiting' && !options[:waiting_enabled]
    if options[:fallback] == 'default_team'
      raise ArgumentError unless options[:fallback_team_id].is_a?(Integer) && options[:fallback_team_id].positive?
    elsif options[:fallback_team_id]
      raise ArgumentError
    end
  end
  private_class_method :validate_connection_options!

  def self.validate_connection_mode!(mode, enabled, team_ids)
    raise ArgumentError unless %w[round_robin priority direct].include?(mode) && (!enabled || team_ids.present?)
    raise ArgumentError if mode == 'direct' && team_ids.size != 1
  end
  private_class_method :validate_connection_mode!

  def self.validate_connection_access!(account, inbox, actor, team_ids)
    raise ArgumentError unless account.account_users.exists?(user_id: actor.id, role: :administrator)
    raise ArgumentError unless inbox.account_id == account.id && account.inboxes.exists?(id: inbox.id)
    raise ArgumentError unless account.teams.where(id: team_ids, allow_auto_assign: true).count == team_ids.size
  end
  private_class_method :validate_connection_access!

  def self.persist_connection!(account, inbox, actor, value)
    before = connection_for(account, inbox.id)
    settings = account.custom_attributes.fetch('jrc_human_assignment', {})
    account.update!(custom_attributes: account.custom_attributes.merge(
      'jrc_human_assignment' => settings.merge('connections' => connections(account).merge(inbox.id.to_s => value))
    ))
    JrcHumanAssignmentPolicyEvent.create!(account_id: account.id, inbox_id: inbox.id, user_id: actor.id,
                                          previous_policy: before || {}, next_policy: value)
    value
  end
  private_class_method :persist_connection!

  def self.record_cursor!(account, inbox_id, agent_id:, team_id:)
    settings = account.custom_attributes.fetch('jrc_human_assignment')
    current = connection_for(account, inbox_id)
    updated = if current
                settings.merge('connections' => connections(account).merge(inbox_id.to_s => current.merge(
                  'last_agent_id' => agent_id, 'last_team_id' => team_id
                )))
              else
                settings.merge('last_agent_id' => agent_id)
              end
    account.update!(custom_attributes: account.custom_attributes.merge('jrc_human_assignment' => updated))
  end

  def self.update!(account, enabled:, max_open:, inbox_ids:)
    validate_limits!(enabled, max_open)
    validate_inbox_ids!(inbox_ids)
    raise ArgumentError if enabled && inbox_ids.empty?

    account.with_lock do
      raise ArgumentError unless account.inboxes.where(id: inbox_ids).count == inbox_ids.size

      persist_global!(account, { enabled: enabled, max_open: max_open, inbox_ids: inbox_ids }, global_actor_id(account))
    end
    self.for(account).slice(:enabled, :max_open, :inbox_ids)
  end

  def self.global_actor_id(account)
    actor = Current.user
    return unless actor

    raise ArgumentError unless account.account_users.exists?(user_id: actor.id, role: :administrator)

    actor.id
  end
  private_class_method :global_actor_id

  def self.persist_global!(account, policy, actor_id)
    before = global_snapshots(account, policy[:inbox_ids])
    previous = account_global_snapshot(self.for(account))
    following = account_global_snapshot(policy)
    current = account.custom_attributes['jrc_human_assignment'] || {}
    account.update!(custom_attributes: account.custom_attributes.merge('jrc_human_assignment' => current.merge(policy.stringify_keys)))
    audit_global_changes!(account, before, actor_id)
    return if previous == following

    JrcHumanAssignmentPolicyEvent.create!(account_id: account.id, inbox_id: nil, user_id: actor_id,
                                          previous_policy: previous, next_policy: following)
  end
  private_class_method :persist_global!

  def self.account_global_snapshot(policy)
    { 'scope' => 'GLOBAL_ACCOUNT', 'enabled' => policy[:enabled], 'max_open' => policy[:max_open], 'inbox_ids' => policy[:inbox_ids] }
  end
  private_class_method :account_global_snapshot

  def self.global_snapshots(account, inbox_ids)
    base = self.for(account)
    ids = (base[:inbox_ids] + inbox_ids).uniq - connections(account).keys.map(&:to_i)
    account.inboxes.where(id: ids).order(:id).pluck(:id).index_with { |id| global_snapshot(base, id) }
  end
  private_class_method :global_snapshots

  def self.global_snapshot(policy, inbox_id)
    included = policy[:inbox_ids].include?(inbox_id)
    { 'scope' => 'GLOBAL', 'enabled' => policy[:enabled] && included, 'included' => included, 'max_open' => policy[:max_open] }
  end
  private_class_method :global_snapshot

  def self.audit_global_changes!(account, before, actor_id)
    policy = self.for(account)
    before.each do |inbox_id, previous|
      following = global_snapshot(policy, inbox_id)
      next if previous == following

      JrcHumanAssignmentPolicyEvent.create!(account_id: account.id, inbox_id: inbox_id, user_id: actor_id,
                                            previous_policy: previous, next_policy: following)
    end
  end
  private_class_method :audit_global_changes!

  def self.validate_limits!(enabled, max_open)
    raise ArgumentError unless [true, false].include?(enabled) && max_open.is_a?(Integer) && max_open.between?(1, 100)
  end
  private_class_method :validate_limits!

  def self.validate_inbox_ids!(inbox_ids)
    raise ArgumentError unless inbox_ids.is_a?(Array) && inbox_ids.size <= 1000
    raise ArgumentError unless inbox_ids.all? { |id| id.is_a?(Integer) && id.positive? } && inbox_ids.uniq == inbox_ids
  end
  private_class_method :validate_inbox_ids!
end
