# Directions are not unrestricted edits. A versioned route points to a native
# policy; absent configuration is a blocking state, never an implied manager.
class JrcApprovals::ReviewDirectivePolicy
  KINDS = %w[request_adjustment suggest_redaction escalate].freeze
  def self.validate!(value)
    unless value.is_a?(Hash) && value.keys.sort == %w[actions escalation_policy_id] && value['actions'].is_a?(Array) &&
      value['actions'].any? && value['actions'].uniq == value['actions'] && (value['actions'] - KINDS).empty?
      raise JrcApprovals::Error, 'INVALID_REVIEW_DIRECTIONS'
    end
    target = value['escalation_policy_id']
    if value['actions'].include?('escalate')
      raise JrcApprovals::Error, 'ESCALATION_CONFIGURATION_REQUIRED' unless target.is_a?(Integer) && target.positive?
    elsif !target.nil?
      raise JrcApprovals::Error, 'INVALID_REVIEW_DIRECTIONS'
    end
    value
  end
  def self.input!(config, kind, text)
    validate!(config)
    raise JrcApprovals::Error, 'REVIEW_DIRECTION_NOT_ALLOWED' unless config['actions'].include?(kind)
    raise JrcApprovals::Error, 'REASON_REQUIRED' unless text.is_a?(String) && text.strip.length.between?(1, 4000)
    text.strip
  end
end
