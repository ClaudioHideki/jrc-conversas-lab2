class JrcRelationship::RefreshJob < ApplicationJob
  queue_as :low

  def perform(membership_id, assignment_ids)
    membership = AccountUser.find_by(id: membership_id)
    return unless membership && membership.account.feature_enabled?('jrc_relationship')
    policy = JrcRelationship::ModulePolicy.new({ account: membership.account, user: membership.user, account_user: membership }, membership.account)
    return unless policy.access?
    context = JrcRelationship::Context.new(membership)
    context.assignments.where(id: Array(assignment_ids).first(200)).find_each do |assignment|
      JrcRelationship::Processor.new(context: context, assignment: assignment).call
    end
  end
end
