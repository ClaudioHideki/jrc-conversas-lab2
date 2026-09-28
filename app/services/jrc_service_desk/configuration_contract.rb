# frozen_string_literal: true

# Closed transport contract. No class/table/column is resolved from a client name.
class JrcServiceDesk::ConfigurationContract
  FIELDS = {
    'queues' => %w[name code active team_id], 'categories' => %w[name code active],
    'priorities' => %w[name code active position], 'statuses' => %w[name code active phase position initial],
    'services' => %w[name code active]
  }.transform_values(&:freeze).freeze
  PHASES = %w[open waiting resolved closed cancelled].freeze

  def self.attributes(resource, value, create:)
    allowed = FIELDS.fetch(resource.to_s)
    allowed -= ['code'] unless create
    data = JrcServiceDesk::Input.attributes(value, allowed)
    raise ArgumentError, 'No configuration fields' if data.empty?
    required = FIELDS.fetch(resource.to_s) - ['team_id']
    raise ArgumentError, 'Explicit configuration required' if create && (required - data.keys).any?
    data.each do |key, field|
      case key
      when 'name', 'code'
        limit = key == 'code' ? 80 : 255
        raise ArgumentError, 'Invalid text' unless field.is_a?(String) && !field.strip.empty? && field.length <= limit
      when 'active', 'initial'
        raise ArgumentError, 'Explicit boolean required' unless [true, false].include?(field)
      when 'phase'
        raise ArgumentError, 'Unknown phase' unless PHASES.include?(field)
      when 'position'
        raise ArgumentError, 'Invalid position' unless field.is_a?(Integer) && field.between?(0, 2_147_483_647)
      when 'team_id'
        data[key] = field.nil? ? nil : JrcServiceDesk::Input.id(field)
      end
    end
    data
  end

  def self.revision(value)
    raise ArgumentError, 'Explicit revision required' unless value.is_a?(String) && value.match?(/\A[a-f0-9]{64}\z/)
    value
  end
end
