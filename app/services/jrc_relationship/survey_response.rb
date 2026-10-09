class JrcRelationship::SurveyResponse
  ANSWER_TYPES = %w[scale choice text].freeze

  def initialize(survey)
    @survey = survey
  end

  def self.visible_question?(question, answers)
    condition = question['condition']
    return true unless condition

    previous = answers[condition['question']]
    return false if previous.nil?

    case condition['operator']
    when 'eq' then previous.to_s == condition['value'].to_s
    when 'lte', 'gte' then numeric_condition(previous, condition)
    end
  end

  def self.numeric_condition(previous, condition)
    number = Float(previous, exception: false)
    return unless number

    condition['operator'] == 'lte' ? number <= condition['value'].to_f : number >= condition['value'].to_f
  end
  private_class_method :numeric_condition

  def call(answers:, comment: nil, native_response_id: nil)
    @survey.with_lock do
      next @survey if native_replay?(native_response_id)
      raise ArgumentError, 'Survey expired or already answered' if @survey.responded_at || @survey.expires_at <= Time.current

      persist_response!(answers, comment, native_response_id)
      audit_response!
      recovery! if %w[detractor low].include?(@survey.classification)
      @survey
    end
  end

  # Local voice/administrative previews use the same published parser without
  # writing a response, invoking recovery, or dispatching any provider request.
  def preview(answers:)
    values = validate_answers(answers.to_h.stringify_keys)
    first = @survey.questions.first
    numeric = first['type'] == 'scale' ? values[first['key']] : nil
    { answers: values, score: numeric, classification: classify(numeric) }
  end

  private

  def native_replay?(native_response_id)
    @survey.responded_at && native_response_id && @survey.metadata['native_csat_response_id'] == native_response_id
  end

  def persist_response!(answers, comment, native_response_id)
    values = validate_answers(answers.to_h.stringify_keys)
    first = @survey.questions.first
    numeric = first['type'] == 'scale' ? values[first['key']] : nil
    @survey.update!(answers: values, score: numeric, comment: comment, classification: classify(numeric),
                    responded_at: Time.current, status: 'responded',
                    metadata: @survey.metadata.merge('native_csat_response_id' => native_response_id).compact)
  end

  def audit_response!
    JrcCustomers::Audit.record!(account: @survey.account, actor: nil, resource: @survey, event_type: 'relationship_updated',
                                metadata: { action: 'survey_responded', assignment_id: @survey.assignment_id,
                                            source_type: @survey.source_type, source_id: @survey.source_id,
                                            rule_version: @survey.rule_version, classification: @survey.classification })
  end

  def validate_answers(answers)
    raise ArgumentError, 'Unknown answer' unless (answers.keys - @survey.questions.pluck('key')).empty?

    @survey.questions.each_with_object({}) do |q, result|
      next unless self.class.visible_question?(q, result)

      value = answers[q['key']]
      validate_required_answer!(q, value)
      next if value.nil? || value == ''

      result[q['key']] = validated_answer(q, value) if ANSWER_TYPES.include?(q['type'])
    end
  end

  def validate_required_answer!(question, value)
    raise ArgumentError, 'Required answer missing' if question['required'] && value.blank? && value != 0
  end

  def validated_answer(question, value)
    case question['type']
    when 'scale' then validated_scale(question, value)
    when 'choice' then validated_choice(question, value)
    when 'text'
      raise ArgumentError, 'Answer too long' unless value.is_a?(String) && value.length <= 4000

      value
    end
  end

  def validated_choice(question, value)
    raise ArgumentError, 'Invalid published option' unless question['options'].any? { |option| option['value'] == value }

    value
  end

  def validated_scale(question, value)
    number = Integer(value.to_s, exception: false)
    raise ArgumentError, 'Answer outside the published scale' unless number&.between?(question['min'], question['max'])

    number
  end

  def classify(score)
    return 'unclassified' unless score

    return classify_nps(score) if @survey.kind == 'nps'

    low_score?(score) ? 'low' : 'satisfied'
  end

  def classify_nps(score)
    return 'detractor' if score <= 6
    return 'neutral' if score <= 8

    'promoter'
  end

  def low_score?(score)
    threshold = @survey.definition_snapshot.dig('settings', 'low_threshold')
    adverse = @survey.kind == 'ces' && @survey.definition_snapshot.dig('settings', 'ces_direction') == 'lower_is_better'
    threshold && (adverse ? score >= threshold : score <= threshold)
  end

  def recovery!
    return unless @survey.assignment && @survey.definition_snapshot.dig('settings', 'recovery_enabled') == true
    return unless JrcRelationship::SurveyEngine.enabled?(@survey.account)

    context = recovery_context
    context.assignment(@survey.assignment_id, write: true)
    key = "survey-response:#{@survey.id}:recovery"
    @survey.assignment.with_lock do
      risk = JrcRelationship::RiskCase.find_or_initialize_by(account: @survey.account, assignment: @survey.assignment, source_key: key)
      create_recovery!(risk, context, key) if risk.new_record?
    end
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    @survey.update!(metadata: @survey.metadata.merge('recovery_status' => 'blocked_access'))
  end

  def create_recovery!(risk, context, key)
    hours = @survey.definition_snapshot.dig('settings', 'recovery_sla_hours') ||
            context.configuration(@survey.assignment).effective_rules['detractor_sla_hours']
    risk.assign_attributes(owner: @survey.assignment.owner, kind: 'satisfaction', severity: 'high',
                           reason: 'Recuperação da resposta de pesquisa', due_at: hours.hours.from_now,
                           metadata: { 'survey_id' => @survey.id, 'response_effect_key' => key,
                                       'source_type' => @survey.source_type, 'source_id' => @survey.source_id })
    JrcRelationship::RiskFinancialSnapshot.capture!(risk, context)
    risk.save!
    JrcRelationship::Workflow.new(context).project_risk!(risk)
    record_recovery!(risk, context, key)
  end

  def record_recovery!(risk, context, key)
    action = @survey.assignment.actions.find_by("metadata ->> 'relationship_risk_id' = ?", risk.id.to_s)
    @survey.update!(metadata: @survey.metadata.merge('recovery_risk_id' => risk.id, 'recovery_action_id' => action&.id,
                                                     'response_effect_key' => key))
    context.audit!(risk, action: 'survey_recovery_created')
  end

  def recovery_context
    member = AccountUser.find_by!(id: @survey.execution_member_id, account_id: @survey.account_id)
    context = JrcRelationship::Context.new(member)
    source = @survey.source_type.constantize.find_by!(id: @survey.source_id, account_id: @survey.account_id)
    origin = JrcRelationship::SurveySource.new(source, context, contract_id: @survey.contract_id, product_id: @survey.product_id)
    validate_recovery_recipient!(origin)
    validate_recovery_snapshot!('commercial_origin', origin.commercial_origin_signature)
    validate_recovery_snapshot!('attendance_origin', origin.attendance_origin_signature)

    context
  end

  def validate_recovery_recipient!(origin)
    raise Pundit::NotAuthorizedError unless origin.contact&.id == @survey.contact_id && !origin.contact.blocked?

    validate_recovery_commercial!(origin)
    return unless @survey.rule_snapshot.dig('settings', 'consent_required')

    raise Pundit::NotAuthorizedError unless origin.contact.custom_attributes['survey_consent'] == true
  end

  def validate_recovery_commercial!(origin)
    raise Pundit::NotAuthorizedError unless origin.contract&.id == @survey.contract_id && origin.product&.id == @survey.product_id
  end

  def validate_recovery_snapshot!(key, signature)
    raise Pundit::NotAuthorizedError if @survey.metadata.key?(key) && @survey.metadata[key] != signature
  end
end
