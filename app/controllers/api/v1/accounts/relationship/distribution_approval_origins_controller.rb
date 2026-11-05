class Api::V1::Accounts::Relationship::DistributionApprovalOriginsController < Api::V1::Accounts::Relationship::BaseController
  def show
    response.headers['Cache-Control'] = 'no-store'
    result = JrcRelationship::BatchReview.transaction do
      authority = JrcRelationship::BatchReviewAuthority.new(account_id: Current.account.id, actor_id: Current.user.id, write: false)
      authority.call do |context|
        review = JrcRelationship::BatchReview.where(account_id: Current.account.id).find(params[:id])
        JrcRelationship::DistributionApprovalCatalog.context(review, Current.user)
        present(review, context)
      end
    end
    render json: result
  end

  private

  def present(review, context)
    { id: review.id, digest: review.digest, expires_at: review.expires_at, state: review.state,
      justification: review.inputs['justification'], distribution: review.snapshot['distribution'] || [],
      capacity: JrcRelationship::DistributionCapacity.new(context).for_view(review),
      responsibilities: JrcRelationship::ResponsibilityReview.new(context).for_view(review) }
  end
end
