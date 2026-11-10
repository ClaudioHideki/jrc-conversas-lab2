# Withdrawal inventory may count pending CS intentions only within current
# native customer and group metadata scope. It never exposes another actor's
# private frozen review or grants permission to cancel their operation.
class JrcRelationship::WithdrawalReviewedOperations
  def initialize(context, analyst)
    @context = context
    @analyst = analyst
  end

  def source
    JrcRelationship::BatchReview.where(account_id: @context.account.id, actor_id: @analyst.id, state: %w[previewed running])
  end

  def visible
    groups = JrcRelationship::PortfolioGroupScope.resolve(@context).select(Arel.sql('jrc_relationship_portfolio_groups.id::text'))
    source.where.not(id: outside_allocations)
          .where.not(id: outside_master_subjects)
          .where("COALESCE(inputs ->> 'operation', '') NOT IN (?) OR inputs ->> 'portfolio_group_id' IN (?)",
                 %w[portfolio_membership master_allocation], groups)
  end

  private

  def outside_allocations
    JrcRelationship::BatchItem.where(account_id: @context.account.id).where.not(assignment_id: nil)
                              .where.not(assignment_id: @context.assignments.select(:id)).select(:batch_review_id)
  end

  def outside_master_subjects
    companies = JrcRelationship::MasterAllocationSources.new(@context).companies.select(:id)
    JrcRelationship::BatchItem.where(account_id: @context.account.id).where.not(company_id: nil)
                              .where.not(company_id: companies).select(:batch_review_id)
  end
end
