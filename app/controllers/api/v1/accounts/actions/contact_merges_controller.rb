class Api::V1::Accounts::Actions::ContactMergesController < Api::V1::Accounts::BaseController
  before_action :set_base_contact, only: [:create]
  before_action :set_mergee_contact, only: [:create]

  rescue_from JrcCustomers::MergePreserver::Conflict do |error|
    render json: { error: error.message, code: 'REVIEW_REQUIRED' }, status: :conflict
  end

  def create
    authorize :directory, :administer?, policy_class: JrcCustomers::DirectoryPolicy if Current.account.feature_enabled?('jrc_customer_master')
    if JrcCustomers::SigningIdentity.where(account_id: Current.account.id, contact_id: [@base_contact.id, @mergee_contact.id]).exists?
      member = Current.account.account_users.find_by(user_id: Current.user.id)
      raise Pundit::NotAuthorizedError unless member&.administrator?
    end
    contact_merge_action = ContactMergeAction.new(
      account: Current.account,
      base_contact: @base_contact,
      mergee_contact: @mergee_contact
    )
    contact_merge_action.perform
  end

  private

  def set_base_contact
    @base_contact = contacts.find(params[:base_contact_id])
  end

  def set_mergee_contact
    @mergee_contact = contacts.find(params[:mergee_contact_id])
  end

  def contacts
    @contacts ||= JrcBroker::GroupContactAccess.new(account: Current.account, user: Current.user || @resource)
                                             .restrict(JrcCustomers::ContactDirectory.covered_scope(account: Current.account, actor: Current.user || @resource))
  end
end
