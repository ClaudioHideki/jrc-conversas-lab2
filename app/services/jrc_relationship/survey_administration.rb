class JrcRelationship::SurveyAdministration
  MODELS = { 'definitions' => JrcRelationship::SurveyDefinition, 'rules' => JrcRelationship::SurveyRule }.freeze

  def initialize(context)
    @context = context
    raise Pundit::NotAuthorizedError unless context.policy.configure?
  end

  def save(kind:, attributes:, id: nil, expected_version: nil)
    model = MODELS.fetch(kind)
    row = id ? model.where(account: @context.account).find(id) : model.new(account: @context.account)
    row.transaction do
      row.lock! if row.persisted?
      validate_version!(row, expected_version)

      before = row.persisted? ? row.snapshot : {}
      capture!(row) if row.persisted?
      row.assign_attributes(attributes)
      row.version += 1 if row.persisted?
      validate_executor!(row)
      JrcRelationship::SurveyRuleTemplate.new(row).normalize! if row.is_a?(JrcRelationship::SurveyRule)
      row.save!
      capture!(row)
      @context.audit!(row, before: before, after: row.snapshot, action: 'survey_configuration_versioned')
      row
    end
  end

  def duplicate(kind:, id:, code: nil)
    row = MODELS.fetch(kind).where(account: @context.account).find(id)
    attrs = row.attributes.except('id', 'account_id', 'created_at', 'updated_at', 'version')
    attrs['name'] = "#{row.name} (copy)".first(120)
    if kind == 'definitions'
      attrs['status'] = 'draft'
      attrs['code'] = code
    end
    attrs['active'] = false if kind == 'rules'
    save(kind: kind, attributes: attrs)
  end

  private

  def validate_version!(row, expected_version)
    raise ActiveRecord::StaleObjectError.new(row, 'update') if row.persisted? && expected_version.to_s != row.version.to_s
  end

  def validate_executor!(row)
    return unless row.is_a?(JrcRelationship::SurveyRule)

    member = row.execution_member
    return unless member

    allowed = @context.assignable_users.exists?(member.user_id) && member.account_id == @context.account.id
    raise Pundit::NotAuthorizedError unless allowed
  end

  def capture!(row)
    JrcRelationship::SurveyVersion.create_or_find_by!(account: @context.account, entity_type: row.class.name,
                                                      entity_id: row.id, version: row.version) do |version|
      version.actor = @context.user
      version.payload = row.snapshot
    end
  end
end
