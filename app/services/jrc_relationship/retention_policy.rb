# Approved business definition, 2026-11-09. Status mapping is explicitly
# configured; unknown history is never replaced by current status or zero.
class JrcRelationship::RetentionPolicy
  STATUSES = %w[onboarding active at_risk churned inactive].freeze
  CONTACT_MODES = %w[relationship_status registered_contact].freeze
  KEYS = %w[eligible_statuses contact_mode target_percent].freeze

  def self.normalize!(input)
    raise ArgumentError, 'Configure the retention eligibility policy' unless input.is_a?(Hash)
    row = input.transform_keys(&:to_s)
    raise ArgumentError, 'Unknown retention policy fields' unless (row.keys - KEYS).empty?
    statuses = row['eligible_statuses']
    unless statuses.is_a?(Array) && statuses.any? && statuses.uniq == statuses && (statuses - STATUSES).empty?
      raise ArgumentError, 'Select explicit native eligible customer statuses'
    end
    raise ArgumentError, 'Select the contact eligibility source' unless CONTACT_MODES.include?(row['contact_mode'])
    target = row['target_percent']
    unless target.nil? || (target.is_a?(Numeric) && target.finite? && target.between?(0, 100))
      raise ArgumentError, 'Retention target must be between zero and one hundred'
    end
    row.merge('eligible_statuses' => statuses.sort)
  end

  def self.eligible?(state, policy)
    return nil unless state.is_a?(Hash) && [true, false].include?(state['source_present'])
    return false unless state['source_present']
    return nil unless STATUSES.include?(state['status'])
    return false unless policy.fetch('eligible_statuses').include?(state['status'])
    case state['customer_type']
    when 'company'
      [true, false].include?(state['master_active']) ? state['master_active'] : nil
    when 'contact'
      return true if policy.fetch('contact_mode') == 'relationship_status'
      return nil unless %w[provisional registered].include?(state['registration_status'])
      state['registration_status'] == 'registered'
    end
  end
end
