class JrcRelationship::PlaybookInput
  def self.call(request:, params:)
    input = submitted_object(request, params)
    raise ArgumentError, 'Playbook must be an object' unless input.is_a?(Hash) || input.is_a?(ActionController::Parameters)

    validate_collections!(input)
    input = ActionController::Parameters.new(input) if input.is_a?(Hash)
    input.permit(:name, :trigger_kind, :active,
                 steps: [:kind, :title, :after_days, :step_key, *JrcRelationship::PlaybookSteps::FLOW_FIELDS],
                 conditions: [:field, :operator, :value])
  end

  def self.submitted_object(request, params)
    return params.require(:playbook) unless request.media_type == 'application/json'

    body = ActiveSupport::JSON.decode(request.raw_post)
    body['playbook'] if body.is_a?(Hash)
  end
  private_class_method :submitted_object

  def self.validate_collections!(input)
    # Rails removes null array entries before strong parameters. Validate the
    # original JSON so malformed conditions cannot become unconditional rules.
    %w[steps conditions].each do |key|
      next unless input.key?(key)

      entries = input[key]
      valid = entries.is_a?(Array) && entries.all? { |entry| entry.is_a?(Hash) || entry.is_a?(ActionController::Parameters) }
      raise ArgumentError, "Playbook #{key} must contain only objects" unless valid
    end
  end
  private_class_method :validate_collections!
end
