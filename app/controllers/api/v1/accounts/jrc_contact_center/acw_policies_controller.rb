# frozen_string_literal: true

class Api::V1::Accounts::JrcContactCenter::AcwPoliciesController < Api::V1::Accounts::JrcContactCenter::BaseController
  def show
    authorize_contact_center!
    render_policy(JrcContactCenter::AcwPolicy.new(account: Current.account))
  end

  def update
    JrcContactCenter::AuthorityTransaction.call(account: Current.account, member: Current.account_user) do
      authorize_contact_center!(:configure?)
      authorize_global_configuration!
      policy = JrcContactCenter::AcwPolicy.new(account: Current.account)
      mode = params.key?(:voice_required) ? params[:voice_required] : :unchanged
      policy.update!(params.require(:limits).permit(:voice, :whatsapp), voice_required: mode, **configuration_revision_options)
      render_policy(policy)
    end
  end

  private

  def render_policy(policy)
    response.headers['Cache-Control'] = 'no-store'
    item = policy.call.merge(id: Current.account.id.to_s, revision: policy.revision)
    render json: base_payload.merge(item: item)
  end

  def authorize_global_configuration!
    coverage = JrcCrm::CorporateCoverage.new(account: Current.account, user: Current.user)
    raise Pundit::NotAuthorizedError if coverage.configured? && !coverage.group?
  end
end
