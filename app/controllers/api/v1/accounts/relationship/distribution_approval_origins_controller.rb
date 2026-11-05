class Api::V1::Accounts::Relationship::DistributionApprovalOriginsController < Api::V1::Accounts::Relationship::BaseController
  def show
    response.headers['Cache-Control'] = 'no-store'
    review = JrcRelationship::BatchReview.where(account_id: Current.account.id).find(params[:id])
    JrcRelationship::DistributionApprovalCatalog.context(review, Current.user)
    render json: { id: review.id, digest: review.digest, expires_at: review.expires_at, state: review.state,
                   justification: review.inputs['justification'], distribution: review.snapshot['distribution'] || [] }
  end
end
