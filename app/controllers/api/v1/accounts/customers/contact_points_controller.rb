class Api::V1::Accounts::Customers::ContactPointsController < Api::V1::Accounts::Customers::BaseController
  before_action :set_contact

  def create
    @contact.with_lock do
      raise ActionController::BadRequest, 'Maximum of 50 directory channels per contact' if @contact.contact_points.count >= 50
      point = @contact.contact_points.create!(point_params.merge(account_id: Current.account.id))
      audit(point, 'created')
      render json: { payload: point }, status: :created
    end
  end

  def update
    @contact.with_lock do
      point = @contact.contact_points.where(account_id: Current.account.id).find(params[:id])
      before = point.attributes
      point.update!(point_params)
      audit(point, 'updated', before)
      render json: { payload: point }
    end
  end

  def destroy
    @contact.with_lock do
      point = @contact.contact_points.where(account_id: Current.account.id).find(params[:id])
      audit(point, 'removed')
      point.destroy!
    end
    head :no_content
  end

  private

  def set_contact
    @contact = Current.account.contacts.find(params[:contact_id])
  end

  def point_params
    params.require(:contact_point).permit(:kind, :value, :label)
  end

  def audit(point, action, previous = nil)
    JrcCustomers::Audit.record!(account: Current.account, actor: Current.user, resource: @contact,
                                event_type: 'customer_contact_point_changed', metadata: { action: action },
                                from_value: previous, to_value: point.attributes)
  end
end
