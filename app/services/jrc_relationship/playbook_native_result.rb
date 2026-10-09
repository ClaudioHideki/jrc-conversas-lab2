# Read-only projection of the native records produced by a mixed published playbook.
class JrcRelationship::PlaybookNativeResult
  KINDS = %w[action activity meeting success_plan risk].freeze
  WORKFLOW_MODELS = { 'risk' => JrcRelationship::RiskCase, 'success_plan' => JrcRelationship::SuccessPlan }.freeze

  def initialize(context:, assignment:)
    @context = JrcRelationship::Context.new(context.member)
    @assignment = @context.assignment(assignment.id)
  end

  def native_step?(execution:, result:)
    validate_scope!(execution)
    step = snapshot_step(execution, result)
    result['reason'] == 'native_execution_pending' && step && KINDS.include?(step['kind'])
  end

  def project(execution:, result:)
    validate_scope!(execution)
    return blocked(result, 'native_origin_changed') unless published_snapshot?(execution)

    step = snapshot_step(execution, result)
    return blocked(result, 'native_origin_changed') unless step && KINDS.include?(step['kind'])

    record = native_record(step, result.fetch('step_key'))
    return blocked(result, 'native_permission_unavailable') unless record && activity_visible?(record)

    result.except('approval_token').merge(
      'state' => 'planned', 'reason' => nil, 'resource_type' => record.class.name,
      'resource_id' => record.id, 'activity_id' => record.try(:activity_id)
    )
  end

  private

  def validate_scope!(execution)
    return if execution.persisted? && execution.account_id == @context.account.id && execution.assignment_id == @assignment.id

    raise Pundit::NotAuthorizedError
  end

  def snapshot_step(execution, result)
    index = Array(execution.step_source_keys).index(result['step_key'])
    Array(execution.snapshot['steps'])[index] if index
  end

  def published_snapshot?(execution)
    return false unless JrcRelationship::Playbook.where(account: @context.account).exists?(execution.playbook_id)

    version = JrcRelationship::PlaybookVersion.find_by(account: @context.account, playbook_id: execution.playbook_id, version: execution.version)
    version && version.payload['active'] == true && version.payload == execution.snapshot.except('results')
  end

  def native_record(step, key)
    model = WORKFLOW_MODELS[step['kind']]
    if model
      @context.records(model).where(assignment: @assignment).find_by("metadata ->> 'playbook_source_key' = ?", key)
    else
      key = "activity:#{key}" if %w[activity meeting].include?(step['kind'])
      @context.records(JrcRelationship::Action).where(assignment: @assignment).find_by(source_key: key)
    end
  end

  def activity_visible?(record)
    id = record.try(:activity_id)
    return true unless id

    visibility = JrcCustomers::Visibility.new(account: @context.account, user: @context.user, account_user: @context.member)
    activity = visibility.crm(@context.account.jrc_crm_activities, owner: :user_id).find_by(id: id)
    activity && activity_binding?(activity, record) && activity_customer?(activity)
  end

  def activity_binding?(activity, record)
    activity.business_unit_id == @assignment.business_unit_id &&
      activity.metadata['relationship_assignment_id'].to_s == @assignment.id.to_s &&
      activity.metadata['relationship_action_id'].to_s == record.id.to_s && activity.metadata['relationship_source_key'] == record.source_key
  end

  def activity_customer?(activity)
    @assignment.company_id ? activity.company_id == @assignment.company_id : activity.contact_id == @assignment.contact_id
  end

  def blocked(result, reason)
    result.except('approval_token', 'resource_type', 'resource_id', 'activity_id').merge('state' => 'blocked', 'reason' => reason)
  end
end
