# frozen_string_literal: true

# Closed, testable contract. Ownership and authorization are never attributes to mass assign.
module JrcServiceDesk::StructureContract
  RESOURCES = %w[operator_companies units unit_memberships].freeze
  CAPABILITIES = { 'operator_companies' => 'operator_companies_manage', 'units' => 'units_manage',
                   'unit_memberships' => 'unit_memberships_manage' }.freeze
  FIELDS = { 'operator_companies' => %w[code name active], 'units' => %w[code name active operator_company_id],
             'unit_memberships' => %w[unit_id account_user_id active] }.freeze

  def self.attributes(resource, value, create:)
    allowed = FIELDS.fetch(resource.to_s)
    allowed = resource == 'unit_memberships' ? ['active'] : %w[name active] unless create
    data = JrcServiceDesk::Input.attributes(value, allowed)
    raise ArgumentError, 'Explicit fields required' if data.empty? || (create && (allowed - data.keys).any?)
    data.each do |key, field|
      case key
      when 'name', 'code'
        maximum = key == 'code' ? 80 : 255
        raise ArgumentError, 'Invalid text' unless field.is_a?(String) && !field.strip.empty? && field.length <= maximum
      when 'active'
        raise ArgumentError, 'Explicit boolean required' unless field == true || field == false
      else
        data[key] = JrcServiceDesk::Input.id(field)
      end
    end
    data
  end

  def self.reason(value)
    raise ArgumentError, 'Authorization reference required' unless value.is_a?(String) && value.strip.length.between?(3, 500) && !value.match?(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/)
    value.strip
  end

  def self.confirmation(value)
    raise ArgumentError, 'Explicit human confirmation required' unless value == true || value == 'confirmed'
    true
  end

  def self.revision(value)
    raise ArgumentError, 'Revision required' unless value.is_a?(String) && value.match?(/\A[a-f0-9]{64}\z/)
    value
  end
end
