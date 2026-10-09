# frozen_string_literal: true

class JrcServiceDesk::OperationalResourceInput
  FIELDS = %w[name code resource_kind description state priority owner_account_user_id company_id approval_id
              planned_start_at planned_end_at details ticket_ids].freeze
  DETAILS = %w[serial manufacturer location change_type risk rollback_plan resolution].freeze
  TEXT_LIMITS = { 'name' => 255, 'code' => 80, 'description' => 20_000 }.freeze

  def self.call(value, creating:)
    data = JrcServiceDesk::Input.attributes(value, creating ? FIELDS : FIELDS - %w[code resource_kind])
    raise ArgumentError, 'Resource attributes required' if data.empty?
    raise ArgumentError, 'Explicit resource identity required' if creating && (%w[name resource_kind priority] - data.keys).any?

    validate_text!(data)
    validate_details!(data) if data.key?('details')
    parse_dates!(data)
    data
  end

  def self.parse_dates!(data)
    %w[planned_start_at planned_end_at].each do |key|
      data[key] = Time.iso8601(data[key]) if data[key]
    end
  end

  def self.validate_text!(data)
    TEXT_LIMITS.each do |key, limit|
      next unless data.key?(key)

      raise ArgumentError, 'Invalid resource text' unless data[key].nil? || (data[key].is_a?(String) && data[key].size <= limit)
    end
  end

  def self.validate_details!(data)
    details = JrcServiceDesk::Input.attributes(data['details'], DETAILS)
    raise ArgumentError, 'Invalid operational details' unless details.values.all? { |item| item.nil? || (item.is_a?(String) && item.size <= 4000) }

    data['details'] = details
  end
  private_class_method :validate_text!, :validate_details!, :parse_dates!
end
