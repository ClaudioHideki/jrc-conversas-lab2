# frozen_string_literal: true

require 'time'

# Finite contract shared by legacy creation/update and the new workspace.
module JrcServiceDesk::CaseInput
  TEXT = { 'title' => 255, 'description' => 20_000, 'impact' => 20_000, 'cause' => 20_000, 'workaround' => 20_000, 'resolution' => 20_000 }.freeze
  DETAILS = %w[hypothesis evidence_summary action_plan expected_result impact_level].freeze
  LEVELS = %w[low moderate high widespread].freeze
  FIELDS = (TEXT.keys + %w[severity service_id category_id started_at details owner_account_user_id]).freeze

  module_function

  def call(attributes, creating: false)
    allowed = creating ? FIELDS + %w[resource_kind ticket_ids] : FIELDS + %w[status]
    values = JrcServiceDesk::Input.attributes(attributes, allowed)
    raise ArgumentError, 'Attributes required' if values.empty?

    TEXT.each do |key, maximum|
      next unless values.key?(key)

      value = values[key]
      raise ArgumentError, "Invalid #{key}" unless value.nil? || (value.is_a?(String) && value.length <= maximum)
      raise ArgumentError, 'Title required' if key == 'title' && (value.nil? || value.strip.empty?)
    end
    %w[service_id category_id owner_account_user_id].each { |key| values[key] = JrcServiceDesk::Input.id(values[key]) if values[key] }
    raise ArgumentError, 'Invalid severity' if values.key?('severity') && !%w[low normal high critical].include?(values['severity'])
    raise ArgumentError, 'Invalid kind' if values.key?('resource_kind') && !%w[incident problem].include?(values['resource_kind'])

    if values.key?('started_at')
      value = values['started_at']
      raise ArgumentError, 'Date requires an explicit timezone' unless value.is_a?(String) && value.match?(/(?:Z|[+-]\d{2}:\d{2})\z/)

      values['started_at'] = Time.iso8601(value)
    end
    if values.key?('details')
      details = JrcServiceDesk::Input.attributes(values['details'], DETAILS)
      raise ArgumentError, 'Invalid details' unless details.values.all? { |v| v.nil? || (v.is_a?(String) && v.length <= 20_000) }
      raise ArgumentError, 'Invalid impact' if details['impact_level'] && !LEVELS.include?(details['impact_level'])

      values['details'] = details
    end
    values
  end

  def ids(value)
    raise ArgumentError, 'Select from one to one hundred records' unless value.is_a?(Array) && value.any? && value.size <= 100

    parsed = value.map { |id| JrcServiceDesk::Input.id(id) }
    raise ArgumentError, 'Duplicate identifier' unless parsed.uniq.size == parsed.size

    parsed.sort
  end
end
