# Reuse native rule/model grants before revealing automation dependencies.
class JrcRelationship::WithdrawalSurveyRules
  def initialize(context, member)
    @context = context
    @member = member
  end

  def source
    JrcRelationship::SurveyRule.where(account: @context.account, execution_member: @member, active: true)
  end

  def visible
    rows = source.order(:id).limit(JrcRelationship::WithdrawalReadiness::MAX_ROWS + 1).to_a
    raise ArgumentError, 'Too many survey policies for one withdrawal review' if rows.length > JrcRelationship::WithdrawalReadiness::MAX_ROWS

    access = JrcRelationship::SurveyModelAccess.new(@context)
    ids = rows.filter_map do |row|
      model = row.settings['service_desk_model']
      permitted = model.present? ? access.allowed?(model, 'read') : @context.policy.admin? && @context.policy.configure?
      row.id if permitted
    end
    source.where(id: ids)
  end
end
