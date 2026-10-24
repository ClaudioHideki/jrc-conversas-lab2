# frozen_string_literal: true

# Comparisons use published bounds, while score/answers remain the original values.
# Legacy CSAT stays 1..5 and legacy CES 0..10. Never mix raw scales in one average.
class JrcRelationship::SurveyScale
  def self.normalize(score, question, low:, high:)
    return nil unless score.is_a?(Numeric) && question.is_a?(Hash)
    min, max = question.values_at('min', 'max')
    return nil unless min.is_a?(Numeric) && max.is_a?(Numeric) && max > min && score.between?(min, max)
    low + (((score - min).to_f * (high - low)) / (max - min))
  end

  def self.sql(kind, reverse: false)
    raise ArgumentError, 'Unsupported scale' unless %w[csat ces].include?(kind)
    low, high = kind == 'csat' ? [1, 5] : [0, 10]
    min = "(definition_snapshot->'questions'->0->>'min')::numeric"
    max = "(definition_snapshot->'questions'->0->>'max')::numeric"
    value = "CASE WHEN jsonb_exists(definition_snapshot->'settings', 'service_desk_model') " \
            "THEN #{low} + (score - #{min}) * #{high - low}.0 / NULLIF(#{max} - #{min}, 0) ELSE score END"
    return value unless reverse && kind == 'ces'
    "CASE WHEN definition_snapshot->'settings'->>'ces_direction' = 'lower_is_better' THEN 10 - (#{value}) ELSE (#{value}) END"
  end
end
