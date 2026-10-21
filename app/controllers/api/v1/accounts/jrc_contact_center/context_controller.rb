# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::ContextController < Api::V1::Accounts::JrcContactCenter::BaseController
  def show
    authorize_contact_center!
    context = JrcContactCenter::CustomerContext.new(account: Current.account)
    render json: base_payload.merge(context.module_context(user_context: pundit_user, access: contact_center_access))
  end
end
