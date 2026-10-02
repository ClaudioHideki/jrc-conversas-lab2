class Api::V1::Accounts::Customers::AddressesController < Api::V1::Accounts::Customers::BaseController
  before_action :set_company

  def create
    @company.with_lock do
      raise ActionController::BadRequest, 'Maximum of 100 addresses per company' if @company.addresses.count >= 100
      address = @company.addresses.create!(address_params.merge(account_id: Current.account.id))
      audit(address, 'created')
      render json: { payload: address }, status: :created
    end
  end

  def update
    @company.with_lock do
      address = @company.addresses.where(account_id: Current.account.id).find(params[:id])
      before = address.attributes
      address.update!(address_params)
      audit(address, 'updated', before)
      render json: { payload: address }
    end
  end

  def destroy
    @company.with_lock do
      address = @company.addresses.where(account_id: Current.account.id).find(params[:id])
      audit(address, 'removed')
      address.destroy!
    end
    head :no_content
  end

  private

  def set_company
    @company = Current.account.master_companies.find(params[:company_id])
  end

  def address_params
    params.require(:address).permit(:address_type, :postal_code, :street, :number, :complement, :district, :city, :state, :country)
  end

  def audit(address, action, previous = nil)
    JrcCustomers::Audit.record!(account: Current.account, actor: Current.user, resource: @company,
                                event_type: 'customer_address_changed', metadata: { action: action },
                                from_value: previous, to_value: address.attributes)
  end
end
