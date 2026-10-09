# frozen_string_literal: true

# Closed, testable contract. Ownership and authorization are never attributes to mass assign.
module JrcServiceDesk::StructureContract
  RESOURCES = %w[operator_companies units unit_memberships].freeze
  CAPABILITIES = { 'operator_companies' => 'operator_companies_manage', 'units' => 'units_manage',
                   'unit_memberships' => 'unit_memberships_manage' }.freeze
  FIELDS = { 'operator_companies' => %w[code name active], 'units' => %w[code name active operator_company_id],
             'unit_memberships' => %w[unit_id account_user_id active availability capacity skills] }.freeze

  VALIDATORS = { 'name' => :text, 'code' => :text, 'active' => :boolean, 'availability' => :availability,
                 'capacity' => :capacity, 'skills' => :skills, 'unit_id' => :reference, 'account_user_id' => :reference,
                 'operator_company_id' => :reference }.freeze

  def self.attributes(resource, value, create:)
    allowed = FIELDS.fetch(resource.to_s)
    allowed = resource == 'unit_memberships' ? %w[active availability capacity skills] : %w[name active] unless create
    data = JrcServiceDesk::Input.attributes(value, allowed)
    required = resource == 'unit_memberships' ? %w[unit_id account_user_id active] : allowed
    raise ArgumentError, 'Explicit fields required' if data.empty? || (create && (required - data.keys).any?)

    # Dispatch only through the finite fields accepted by Input.attributes.
    data.each { |key, field| data[key] = send(VALIDATORS.fetch(key), key, field) }
    data
  end

  def self.reason(value)
    valid = value.is_a?(String) && value.strip.length.between?(3, 500) && !value.match?(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/)
    raise ArgumentError, 'Authorization reference required' unless valid

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

  def self.text(key, value)
    maximum = key == 'code' ? 80 : 255
    raise ArgumentError, 'Invalid text' unless value.is_a?(String) && !value.strip.empty? && value.length <= maximum

    value
  end

  def self.boolean(_key, value)
    raise ArgumentError, 'Explicit boolean required' unless value == true || value == false

    value
  end

  def self.availability(_key, value)
    raise ArgumentError unless %w[available paused unavailable].include?(value)

    value
  end

  def self.capacity(_key, value)
    raise ArgumentError unless value.nil? || (value.is_a?(Integer) && value.between?(1, 1000))

    value
  end

  def self.skills(_key, value)
    raise ArgumentError unless value.is_a?(Array)

    value
  end

  def self.reference(_key, value)
    JrcServiceDesk::Input.id(value)
  end

  private_class_method :text, :boolean, :availability, :capacity, :skills, :reference
end
