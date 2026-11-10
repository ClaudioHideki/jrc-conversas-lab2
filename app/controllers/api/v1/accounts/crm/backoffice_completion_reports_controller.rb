class Api::V1::Accounts::Crm::BackofficeCompletionReportsController < Api::V1::Accounts::Crm::BaseController
  rescue_from JrcBackoffice::CompletionReport::NotCompleted do
    render json: { code: 'REQUEST_NOT_COMPLETED' }, status: :unprocessable_entity
  end
  rescue_from JrcBackoffice::CompletionReport::TooLarge do
    render json: { code: 'REPORT_TOO_LARGE' }, status: :unprocessable_entity
  end
  prepend_before_action { response.headers['Cache-Control'] = 'no-store' }

  def show
    csv = JrcBackoffice::CompletionReport.new(account: Current.account, actor: Current.user,
                                              request_id: params[:backoffice_request_id]).call
    response.headers['X-Content-Type-Options'] = 'nosniff'
    send_data csv, filename: "backoffice-#{params[:backoffice_request_id].to_i}-completion.csv", type: 'text/csv; charset=utf-8',
                   disposition: 'attachment'
  end
end
