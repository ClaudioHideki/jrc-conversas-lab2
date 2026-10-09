# Prepares an actual published survey for an eventual telephony adapter. This
# service never opens a call, stores answers or pretends that an URA exists.
class JrcRelationship::SurveyVoicePreview
  def initialize(context, survey)
    @context = JrcRelationship::Context.new(context.member)
    @survey = @context.records(JrcRelationship::Survey).find(survey.id)
    validate_current!
  end

  def call(inputs: nil)
    result = { account_id: @context.account.id, survey_id: @survey.id, definition_id: @survey.definition_id,
               definition_version: @survey.definition_version, rule_version: @survey.rule_version,
               dry_run: true, persisted: false, external_status: 'not_configured',
               questions: @survey.questions.map { |question| compile(question) } }
    result[:response_preview] = JrcRelationship::SurveyResponse.new(@survey).preview(answers: answers(inputs)) if inputs
    result
  end

  private

  def validate_current!
    raise ArgumentError, 'Survey expired or already answered' if @survey.responded_at || @survey.expires_at <= Time.current
    raise ArgumentError, 'Survey is not available for response' unless %w[awaiting available sent delivered].include?(@survey.status)
    raise ArgumentError, 'Invalid published questions' unless JrcRelationship::SurveyQuestionSchema.new(@survey.questions).valid?
    return if @survey.source_type.blank?

    reason = JrcRelationship::SurveyExecutionContext.new(@survey).blocker(ignore_activation: true)
    raise Pundit::NotAuthorizedError, reason if reason
  end

  def compile(question)
    base = question.slice('key', 'text', 'required', 'condition')
    case question['type']
    when 'scale'
      base.merge(type: 'scale', capture: 'digits', min: question['min'], max: question['max'], terminator: '#',
                 max_digits: question['max'].to_s.length)
    when 'choice'
      base.merge(type: 'choice', capture: 'digits', terminator: '#', max_digits: question['options'].size.to_s.length,
                 options: question['options'].each_with_index.map { |option, index| option.merge('digit' => (index + 1).to_s) })
    when 'text'
      base.merge(type: 'text', capture: 'transcription', max_length: 4000, external_transcription_required: true)
    end
  end

  def answers(inputs)
    values = inputs.to_h.stringify_keys
    validate_inputs!(values)
    @survey.questions.each_with_object({}) do |question, result|
      next unless values.key?(question['key'])

      result[question['key']] = answer(question, values.fetch(question['key']))
    end
  end

  def validate_inputs!(values)
    raise ArgumentError, 'Unknown voice input' unless (values.keys - @survey.questions.pluck('key')).empty?
    return if values.values.all? { |value| value.nil? || ((value.is_a?(String) || value.is_a?(Numeric)) && value.to_s.length <= 4000) }

    raise ArgumentError, 'Voice input must be a bounded scalar'
  end

  def answer(question, value)
    return value unless question['type'] == 'choice'
    return nil if value.nil? || value == ''

    raise ArgumentError, 'Invalid published voice option' unless value.to_s.match?(/\A[1-9]\d?\z/)

    option = question['options'][value.to_i - 1]
    raise ArgumentError, 'Invalid published voice option' unless option

    option.fetch('value')
  end
end
