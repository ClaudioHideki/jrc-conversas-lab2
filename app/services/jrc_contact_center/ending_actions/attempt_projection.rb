# frozen_string_literal: true

# Allowlist only. Never serialize private templates, answers, notes, exceptions,
# raw audit snapshots, another destination's history or unscoped project titles.
class JrcContactCenter::EndingActions::AttemptProjection
  def initialize(member:)
    @member = member
  end

  def call(attempt)
    raise ActiveRecord::RecordNotFound unless attempt.account_id == @member.account_id

    outcome = attempt.outcome
    execution = outcome&.execution
    { id: attempt.id.to_s, origin_id: attempt.origin_id.to_s, rule_code: attempt.rule_code,
      version_id: attempt.version_id.to_s, destination_kind: attempt.destination_kind,
      request_id: attempt.request_key, queued_at: attempt.created_at.iso8601,
      outcome: outcome&.outcome || 'pending', result_code: outcome&.result_code,
      finished_at: outcome&.created_at&.iso8601, execution_id: execution&.id&.to_s,
      target: visible_project_task(execution) }
  end

  private

  def visible_project_task(execution)
    return unless execution&.destination_kind == 'project_task'

    task = JrcProjects::Task.where(account_id: @member.account_id).find_by(id: execution.target_id)
    return unless task

    project = JrcOperations::Access.projects(@member).find_by(id: task.project_id)
    return unless project && JrcProjects::Authorization.allowed?(account_user: @member, capability: 'projects.task.view', project: project)

    { kind: 'project_task', id: task.id.to_s, project_id: project.id.to_s }
  end
end
