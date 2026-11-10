class Api::V1::Accounts::Relationship::RetentionController < Api::V1::Accounts::Relationship::BaseController
  before_action { response.headers['Cache-Control'] = 'no-store' }

  def show
    render json: JrcRelationship::RetentionReport.new(relationship_context).call(
      period: params.require(:period), reference: params[:reference], from: params[:from], to: params[:to],
      portfolio_group_id: params[:portfolio_group_id])
  end

  def status
    context = relationship_context
    signature = context.access_signature
    row = JrcRelationship::RetentionCoverage.find_by(account_id: context.account.id)
    fresh = JrcRelationship::Context.new(context.member)
    raise Pundit::NotAuthorizedError unless fresh.access_signature == signature && fresh.user.reload.active_for_authentication?
    render json: { started_at: row&.started_at, can_start: fresh.policy.admin? && fresh.policy.configure? }
  end

  def start
    render json: JrcRelationship::RetentionHistory.start!(relationship_context, reason: params.require(:reason))
  end
end
