# frozen_string_literal: true

class JrcServiceDesk::TaskProgression
  def initialize(context:, ticket:, task:)
    @context = context
    @ticket = ticket
    @task = task
  end

  def call
    policy = JrcServiceDesk::TaskCompletionPolicy.new(@task.completion_policy)
    return unless policy.enabled?

    policy.verify!(@context, @ticket)
    raise JrcServiceDesk::IdempotencyConflict unless @task.completion_policy_digest == JrcServiceDesk::CanonicalJson.digest(policy.definition)

    effects = policy.definition
    create_next_task(effects['next_task']) if effects['next_task']
    request_approval(effects['approval']) if effects['approval']
    transition(effects['transition'], effects) if effects['transition']
  end

  private

  def create_next_task(values)
    JrcServiceDesk::CreateTaskService.new(user_context: @context.to_h).call(
      ticket_id: @ticket.id, attributes: values, idempotency_key: "task:#{@task.id}:next"
    )
  end

  def request_approval(values)
    JrcServiceDesk::CreateApprovalService.new(user_context: @context.to_h).call(
      ticket_id: @ticket.id, attributes: values, idempotency_key: "task:#{@task.id}:approval"
    )
  end

  def transition(values, policy)
    JrcServiceDesk::LifecycleTransitionService.new(user_context: @context.to_h).call(
      ticket_id: @ticket.id,
      attributes: values.merge('expected_lock_version' => @ticket.reload.lock_version,
                               'expected_policy_version_id' => policy['lifecycle_policy_version_id']),
      idempotency_key: "task:#{@task.id}:transition"
    )
  end
end
