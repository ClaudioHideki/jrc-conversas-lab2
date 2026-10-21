# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::CustomerContextController < Api::V1::Accounts::JrcContactCenter::BaseController
  def show
    authorize_contact_center!(:operate?)
    raise Pundit::NotAuthorizedError unless contact_center_access.full_access? || contact_center_access.queue_ids.any?

    render json: base_payload.merge(JrcContactCenter::CustomerContext.new(account: Current.account).by_phone(params.require(:phone)))
  end
end
