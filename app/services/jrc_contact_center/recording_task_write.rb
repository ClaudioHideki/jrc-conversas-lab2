# frozen_string_literal: true

# Explicit manual task creation by the current user. This is independent of
# automatic original-agent execution, the human analysis revision and ACW.
class JrcContactCenter::RecordingTaskWrite
  def initialize(account:, member:)
    raise Pundit::NotAuthorizedError unless member && member.account_id == account.id

    @account = account
    @member = member
  end

  def call(record_id, values)
    input = JrcContactCenter::RecordingTaskInput.new(values)
    source = JrcContactCenter::QualityReviewSource.new(account: @account, member: @member, action: :recordings_listen)
    source.with_record(record_id) { |record, call| create_or_reuse(record, call, input) }
  end

  private

  def create_or_reuse(record, call, input)
    raise JrcContactCenter::OperationError, 'recording_task_scope_unavailable' unless call.current_unit_id

    project = authorized_project(input)
    scope = scope_for(call)
    attributes = operation_attributes(record, call, project, input, scope)
    JrcOperations::Idempotency.run(account: @account, actor: @member.user, model: JrcContactCenter::RecordingTaskLink,
                                   key: input.request_id, attributes: attributes) do |key, fingerprint|
      persist(record, call, project, input, scope_snapshot: scope, idempotency_key: key, request_fingerprint: fingerprint)
    end
  rescue ArgumentError
    raise_if_conflicting_request!(input)
    raise
  end

  def operation_attributes(record, call, project, input, scope)
    { recording_id: record.id, call_session_id: call.id, project_id: project.id, task: input.attributes, scope: scope }
  end

  def raise_if_conflicting_request!(input)
    return unless JrcContactCenter::RecordingTaskLink.where(account: @account, idempotency_key: input.request_id).exists?

    raise JrcContactCenter::OperationError.new('recording_task_request_conflict', status: :conflict)
  end

  def authorized_project(input)
    project = JrcOperations::Access.projects(@member).find(input.project_id)
    rights = ['projects.task.create']
    rights << 'projects.task.assign' if input.attributes['assignee_id'].present?
    allowed = rights.all? { |right| JrcProjects::Authorization.allowed?(account_user: @member, capability: right, project: project) }
    raise Pundit::NotAuthorizedError unless allowed

    project
  end

  def persist(record, call, project, input, receipt)
    task = JrcProjects::Tasks::Create.call(account_user: @member, project: project, attributes: input.attributes,
                                           correlation_id: receipt.fetch(:idempotency_key))
    JrcContactCenter::RecordingTaskLink.create!(
      account: @account, recording: record, call_session: call, project_id: project.id, task_id: task.id,
      created_by: @member.user, actor_account_user_id: @member.id, created_at: Time.current, **receipt
    )
  end

  def scope_for(call)
    target = call.current_queue || call.current_unit
    return { 'account_id' => @account.id.to_s } unless target

    JrcContactCenter::ConfigurationAuditSnapshot.capture(target).fetch('scope')
  end
end
