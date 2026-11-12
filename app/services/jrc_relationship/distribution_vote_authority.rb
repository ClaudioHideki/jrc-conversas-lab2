class JrcRelationship::DistributionVoteAuthority
  def self.authorize!(account:, user:, record:)
    return true unless "#{record.module_key}.#{record.event_key}" == JrcRelationship::DistributionApproval::KEY
    review = JrcRelationship::BatchReview.where(account_id: account.id).find(record.resource_id)
    context = JrcRelationship::DistributionApprovalCatalog.context(review, user)
    rows = JrcRelationship::ReviewedAssignmentScope.new(context, review).scope.where(id: review.inputs.fetch('ids'))
    raise Pundit::NotAuthorizedError unless rows.count == review.inputs.fetch('ids').size
    rows.each { |row| JrcRelationship::LocalAccess.authorize_assignment!(context, row, 'approve_transfer') }
    true
  end
end
