class JrcHumanAssignment::Policy
  def self.for(account)
    value = account.custom_attributes['jrc_human_assignment'] || {}
    { enabled: value['enabled'] == true, max_open: value.fetch('max_open', 10), inbox_ids: value.fetch('inbox_ids', []),
      last_agent_id: value.fetch('last_agent_id', 0) }
  end

  def self.enabled?(account)
    self.for(account)[:enabled]
  end

  def self.enabled_for?(account, inbox_id)
    policy = self.for(account)
    policy[:enabled] && policy[:inbox_ids].include?(inbox_id)
  end

  def self.update!(account, enabled:, max_open:, inbox_ids:)
    validate_limits!(enabled, max_open)
    validate_inbox_ids!(inbox_ids)
    raise ArgumentError if enabled && inbox_ids.empty?

    account.with_lock do
      raise ArgumentError unless account.inboxes.where(id: inbox_ids).count == inbox_ids.size

      current = account.custom_attributes['jrc_human_assignment'] || {}
      account.update!(custom_attributes: account.custom_attributes.merge(
        'jrc_human_assignment' => current.merge('enabled' => enabled, 'max_open' => max_open, 'inbox_ids' => inbox_ids)
      ))
    end
    self.for(account).slice(:enabled, :max_open, :inbox_ids)
  end

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
