class JrcRelationship::SurveyExecutionContext
  attr_reader :context, :origin

  def initialize(survey)
    @survey = survey
  end

  def blocker(ignore_activation: false)
    return 'automation_disabled' unless activation_allowed?(ignore_activation)
    return 'expired_or_responded' if expired_or_responded?
    return 'policy_changed' unless current_rule?
    return 'definition_not_available' unless definition_available?

    initialize_origin || recipient_blocker
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    'source_access_denied'
  end

  def conversation
    origin.conversation(@survey.rule_snapshot.dig('settings', 'channel'),
                        inbox_id: @survey.rule_snapshot.dig('settings', 'delivery_inbox_id'))
  end

  private

  def activation_allowed?(ignore_activation)
    ignore_activation || JrcRelationship::SurveyEngine.enabled?(@survey.account)
  end

  def expired_or_responded?
    @survey.responded_at || @survey.expires_at <= Time.current
  end

  def definition_available?
    JrcRelationship::SurveyDefinition.available_at?(@survey.definition_snapshot.fetch('settings', {}), Time.current)
  end

  def initialize_origin
    member = AccountUser.find_by(id: @survey.execution_member_id, account_id: @survey.account_id)
    return 'execution_member_missing' unless member

    @context = JrcRelationship::Context.new(member)
    return 'source_invalid' unless JrcRelationship::SurveySource::TYPES.include?(@survey.source_type)

    source = @survey.source_type.constantize.find_by(id: @survey.source_id, account_id: @survey.account_id)
    return 'source_missing' unless source

    @origin = JrcRelationship::SurveySource.new(source, context, contract_id: @survey.contract_id, product_id: @survey.product_id)
    nil
  end

  def current_rule?
    rule = @survey.rule&.reload
    rule&.active && rule.version == @survey.rule_version && rule.execution_member_id == @survey.execution_member_id &&
      rule.definition.status == 'active'
  end

  def recipient_blocker
    return 'interaction_not_completed' unless origin.completed?
    return 'contact_missing' unless origin.contact
    return 'recipient_changed' unless origin.contact.id == @survey.contact_id

    origin_snapshot_blocker || consent_blocker
  end

  def origin_snapshot_blocker
    return 'attendance_origin_changed' if snapshot_changed?('attendance_origin', origin.attendance_origin_signature)
    return 'commercial_origin_changed' if snapshot_changed?('commercial_origin', origin.commercial_origin_signature)
    return 'commercial_origin_changed' unless origin.contract&.id == @survey.contract_id && origin.product&.id == @survey.product_id

    nil
  end

  def snapshot_changed?(key, signature)
    @survey.metadata.key?(key) && @survey.metadata[key] != signature
  end

  def consent_blocker
    required = @survey.rule_snapshot.dig('settings', 'consent_required')
    return 'contact_or_consent_revoked' if origin.contact.blocked? || (required && origin.contact.custom_attributes['survey_consent'] != true)

    nil
  end
end
