class Api::V1::Accounts::Crm::FunnelsController < Api::V1::Accounts::Crm::BaseController
  def show
    scope = customer_segment_scope(visible_to_current_user(crm_scope.jrc_crm_deals))
    filters = params.permit(:pipeline_id, :team_id, :owner_id, :month, :mode)
    response.headers['Cache-Control'] = 'no-store'
    render json: JrcCrm::FunnelReport.new(account: crm_scope, scope: scope, params: filters).call
  end
end
