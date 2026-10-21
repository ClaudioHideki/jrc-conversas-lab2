# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::AcwPoliciesController < Api::V1::Accounts::JrcContactCenter::BaseController
  def show
    authorize_contact_center!
    render json: base_payload.merge(item: JrcContactCenter::AcwPolicy.new(account: Current.account).call)
  end

  def update
    authorize_contact_center!(:configure?)
    policy = JrcContactCenter::AcwPolicy.new(account: Current.account)
    render json: base_payload.merge(item: policy.update!(params.require(:limits).permit(:voice, :whatsapp)))
  end
end
