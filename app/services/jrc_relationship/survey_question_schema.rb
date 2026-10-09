class JrcRelationship::SurveyQuestionSchema
  SCALES = { 'nps' => [0, 10], 'csat' => [1, 5], 'ces' => [0, 10] }.freeze

  def initialize(questions)
    @questions = questions
  end

  def valid?
    return false unless @questions.is_a?(Array) && @questions.size.between?(1, 20)
    return false unless @questions.all? { |question| valid_question?(question) }
    return false unless @questions.pluck('key').uniq.size == @questions.size

    @questions.each_with_index.all? { |question, index| valid_condition?(question['condition'], index) }
  end

  def principal_scale?(kind)
    return true if kind == 'custom'

    question = @questions.first
    question['type'] == 'scale' && question['required'] == true && SCALES[kind] == [question['min'], question['max']]
  end

  private

  def valid_question?(question)
    return false unless valid_question_header?(question)

    case question['type']
    when 'text' then true
    when 'scale' then valid_scale?(question)
    when 'choice' then valid_choices?(question['options'])
    else false
    end
  end

  def valid_question_header?(question)
    question.is_a?(Hash) && question['key'].to_s.match?(/\A[a-z0-9_-]{1,60}\z/) &&
      bounded_text?(question['text'], 1000) && [true, false].include?(question['required'])
  end

  def valid_scale?(question)
    min, max = question.values_at('min', 'max')
    min.is_a?(Integer) && max.is_a?(Integer) && min >= 0 && max <= 100 && min < max
  end

  def valid_choices?(options)
    return false unless options.is_a?(Array) && options.size.between?(1, 30)

    valid = options.all? { |option| option.is_a?(Hash) && bounded_text?(option['value'], 60) && bounded_text?(option['label'], 120) }
    valid && options.pluck('value').uniq.size == options.size
  end

  def valid_condition?(condition, index)
    return true if condition.nil?
    return false unless condition.is_a?(Hash) && %w[eq lte gte].include?(condition['operator'])
    return false unless @questions.take(index).any? { |prior| prior['key'] == condition['question'] }

    valid_condition_value?(condition)
  end

  def valid_condition_value?(condition)
    value = condition['value']
    valid = (value.is_a?(String) || value.is_a?(Numeric)) && value.to_s.length <= 1000
    valid && (condition['operator'] == 'eq' || Float(value, exception: false)&.finite?)
  end

  def bounded_text?(value, limit)
    value.is_a?(String) && value.length.between?(1, limit)
  end
end
