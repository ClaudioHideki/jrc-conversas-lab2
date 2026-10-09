# frozen_string_literal: true

class JrcServiceDesk::ClockEscalationPolicy
  attr_reader :definition

  def initialize(value)
    @definition = JrcServiceDesk::Input.attributes(value, %w[enabled thresholds automatic execution_account_user_id])
    return if definition.empty?

    raise ArgumentError, 'Explicit clock monitoring switch required' unless [true, false].include?(definition['enabled'])

    validate_thresholds!
    validate_automation!
  end

  def enabled?
    definition['enabled'] == true
  end

  def thresholds
    definition.fetch('thresholds', []).sort_by { |row| row['percent'] }
  end

  def automatic?
    enabled? && definition['automatic'] == true
  end

  def execution_account_user_id
    definition['execution_account_user_id']
  end

  private

  def validate_automation!
    if definition.key?('automatic') && ![true, false].include?(definition['automatic'])
      raise ArgumentError, 'Explicit automatic monitoring switch required'
    end
    if definition.key?('execution_account_user_id') && !definition['execution_account_user_id'].nil?
      definition['execution_account_user_id'] = JrcServiceDesk::Input.id(definition['execution_account_user_id'])
    end
    return unless definition['automatic'] == true

    raise ArgumentError, 'Automatic monitoring requires an enabled policy and an explicit executor' unless enabled? && execution_account_user_id
  end

  def validate_thresholds!
    rows = definition['thresholds']
    raise ArgumentError, 'Explicit threshold list required' unless rows.is_a?(Array) && rows.size.between?(1, 20)

    rows = rows.map { |row| validate_threshold!(row) }
    definition['thresholds'] = rows
    raise ArgumentError, 'Duplicate clock threshold' unless rows.pluck('percent').uniq.size == rows.size
  end

  def validate_threshold!(row)
    values = JrcServiceDesk::Input.attributes(row, %w[percent queue_id team_id])
    raise ArgumentError, 'Explicit threshold fields required' unless values.keys.sort == %w[percent queue_id team_id].sort
    raise ArgumentError, 'Clock threshold must be between 1 and 100' unless values['percent'].is_a?(Integer) && values['percent'].between?(1, 100)

    validate_targets!(values)
    values
  end

  def validate_targets!(values)
    %w[queue_id team_id].each do |key|
      next if values[key].nil?

      values[key] = JrcServiceDesk::Input.id(values[key])
    end

    raise ArgumentError, 'Team escalation requires an explicit queue' if values['team_id'] && !values['queue_id']
  end
end
