class JrcRelationship::RefreshJob < ApplicationJob
  queue_as :low

  def perform(membership_id, assignment_ids)
    membership = AccountUser.find_by(id: membership_id)
    return unless membership && membership.user.active_for_authentication? && membership.account.feature_enabled?('jrc_relationship')
    policy = JrcRelationship::ModulePolicy.new({ account: membership.account, user: membership.user, account_user: membership }, membership.account)
    return unless policy.access?
    context = JrcRelationship::Context.new(membership)
    assignments = context.assignments.where(id: Array(assignment_ids).first(200))
    run = JrcRelationship::ProcessingRun.create!(account: context.account, viewer: context.user, access_signature: context.access_signature,
                                                requested_ids: assignments.pluck(:id), started_at: Time.current)
    outcomes = {}
    error = nil
    assignments.find_each do |assignment|
      begin
        membership.reload
        raise Pundit::NotAuthorizedError unless membership.user.active_for_authentication?

        current_context = JrcRelationship::Context.new(membership)
        current_assignment = current_context.assignment(assignment.id)
        JrcRelationship::Processor.new(context: current_context, assignment: current_assignment).call
        outcomes[assignment.id.to_s] = 'processed'
      rescue StandardError => failure
        # No exception messages, customer content or credentials are stored here.
        outcomes[assignment.id.to_s] = 'processing_failed'
        error ||= failure
      end
    end
    run.update!(outcomes: outcomes, state: error ? 'failed' : 'completed', finished_at: Time.current)
    raise error if error
  end
end
