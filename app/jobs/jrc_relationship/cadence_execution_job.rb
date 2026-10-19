class JrcRelationship::CadenceExecutionJob < ApplicationJob
  queue_as :default
  retry_on ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, wait: 3.seconds, attempts: 3

  def perform(id)
    record = JrcRelationship::CadenceEnrollment.find_by(id: id, state: 'active')
    return unless record

    member = AccountUser.find_by!(account_id: record.account_id, user_id: record.actor_id)
    result = JrcRelationship::ReviewedCadence.new(JrcRelationship::Context.new(member)).advance(id)
    next_at = record.steps.where(state: 'pending').minimum(:due_at) if result.fetch('state') == 'active'
    self.class.set(wait_until: [next_at, 1.second.from_now].max).perform_later(id) if next_at
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    JrcRelationship::ReviewedCadence.stop_revoked(id)
  end
end
