# Read-only evaluation of a pinned plan. Native sources are supplied separately;
# no manually submitted value can impersonate a document, approval or signature.
class JrcBackoffice::RequirementEvaluation
  SATISFIED = %w[satisfied not_applicable].freeze

  def initialize(rows:, facts:, responses:, source:)
    @rows, @facts, @responses, @source = rows, facts, responses, source
  end

  def call(through: nil)
    if through && !JrcBackoffice::RequirementDefinition::STAGES.include?(through)
      raise ArgumentError, 'Unsupported requirement stage'
    end
    @rows.map do |entry|
      definition = JrcBackoffice::RequirementDefinition.normalize(entry.fetch('definition'))
      scope_kind = entry.dig('scope', 'customer_kind')
      result = if scope_kind && @facts['customer_kind'].nil?
                 'unavailable'
               elsif scope_kind && scope_kind != @facts['customer_kind']
                 'not_applicable'
               else
                 evaluate(entry.fetch('key'), definition)
               end
      due = through.nil? || JrcBackoffice::RequirementDefinition::STAGES.index(definition.fetch('stage')) <=
        JrcBackoffice::RequirementDefinition::STAGES.index(through)
      { key: entry.fetch('key'), definition: definition, status: result,
        blocking: due && definition['required'] && definition['blocking'] && !SATISFIED.include?(result),
        response_revision: @responses.dig(entry.fetch('key'), 'revision') || 0 }
    end
  end

  private

  def evaluate(key, definition)
    applicable = JrcBackoffice::RequirementDefinition.applicable(definition, @facts)
    return 'not_applicable' if applicable == false
    return 'unavailable' if applicable == :unknown

    kind = JrcBackoffice::RequirementDefinition.leaf_kind(definition)
    if kind == 'information'
      response = @responses[key]
      return 'missing' unless response && response.key?('value')

      JrcBackoffice::RequirementDefinition.answer!(definition, response['value'])
      return 'satisfied'
    end
    if JrcBackoffice::RequirementDefinition::HUMAN_KINDS.include?(kind)
      response = @responses[key]
      return 'pending' unless response
      JrcBackoffice::RequirementDefinition.response_payload!(definition, response.slice('decision', 'note'))
      return response['decision'] == 'rejected' ? 'rejected' : 'satisfied'
    end
    if kind == 'validation' && definition['source'] == 'manual_review'
      decision = @responses.dig(key, 'decision')
      return 'satisfied' if decision == 'approved'
      return 'rejected' if decision == 'rejected'

      return 'pending'
    end
    state = @source.call(kind, definition)
    raise ArgumentError, 'Native source returned an invalid evidence state' unless
      %w[satisfied missing pending rejected expired quarantined unavailable].include?(state)

    state
  end
end
