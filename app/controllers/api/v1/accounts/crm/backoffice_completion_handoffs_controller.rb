class Api::V1::Accounts::Crm::BackofficeCompletionHandoffsController < Api::V1::Accounts::Crm::BaseController
  rescue_from JrcBackoffice::CompletionReport::NotCompleted do
    render json: { code: 'REQUEST_NOT_COMPLETED' }, status: :unprocessable_entity
  end
  prepend_before_action { response.headers['Cache-Control'] = 'no-store' }

  def show
    render json: JrcBackoffice::CompletionHandoff.new(account: Current.account, actor: Current.user,
                                                      request_id: params[:backoffice_request_id]).call
  end
end
