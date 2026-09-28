# frozen_string_literal: true

# No routes or public actions are registered in CP1.
class Api::V1::Accounts::JrcServiceDesk::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_service_desk_available!
  after_action :verify_authorized
  after_action :verify_policy_scoped, only: :index

  private

  def ensure_service_desk_available!
    return if service_desk_access_context.available?

    head :forbidden
  end

  def service_desk_access_context
    @service_desk_access_context ||= ::JrcServiceDesk::AccessContext.new(pundit_user)
  end
end
