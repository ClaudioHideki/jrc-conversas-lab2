class Api::V1::Accounts::Contacts::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_contact

  private

  def ensure_contact
    @contact = JrcBroker::GroupContactAccess.new(account: Current.account, user: Current.user || @resource)
                                            .restrict(Current.account.contacts).find(params[:contact_id])
  end
end
