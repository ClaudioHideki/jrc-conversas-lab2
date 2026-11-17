# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::AcwPoliciesController < Api::V1::Accounts::JrcContactCenter::BaseController
  def show
    authorize_contact_center!
    render json: base_payload.merge(item: JrcContactCenter::AcwPolicy.new(account: Current.account).call)
  end

  def update
    JrcContactCenter::AuthorityTransaction.call(account: Current.account, member: Current.account_user) do
      authorize_contact_center!(:configure?)
      authorize_global_configuration!
      policy = JrcContactCenter::AcwPolicy.new(account: Current.account)
      mode = params.key?(:voice_required) ? params[:voice_required] : :unchanged
      render json: base_payload.merge(item: policy.update!(params.require(:limits).permit(:voice, :whatsapp), voice_required: mode))
    end
  end

  private

  def authorize_global_configuration!
    coverage = JrcCrm::CorporateCoverage.new(account: Current.account, user: Current.user)
    raise Pundit::NotAuthorizedError if coverage.configured? && !coverage.group?
  end
end
