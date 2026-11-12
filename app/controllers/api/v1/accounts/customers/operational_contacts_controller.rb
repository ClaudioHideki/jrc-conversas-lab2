class Api::V1::Accounts::Customers::OperationalContactsController < Api::V1::Accounts::Customers::BaseController
  def index
    response.headers['Cache-Control'] = 'no-store'
    response.headers['X-Content-Type-Options'] = 'nosniff'
    query = JrcCustomers::OperationalContacts.new(account: Current.account, actor: Current.user)
    render json: query.call(params: params.permit(:q, :status, :kind, :days, :taxonomy_id, :page, :per_page))
  end
end
