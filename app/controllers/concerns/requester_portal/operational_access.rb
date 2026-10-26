# frozen_string_literal: true

# Dashboard HTML requests also need a backend boundary. Native authentication
# screens remain usable for the existing invitation/password recovery workflow.
module RequesterPortal::OperationalAccess
  extend ActiveSupport::Concern
  include DeviseTokenAuth::Concerns::SetUserByToken
  include RequesterPortal::NativeSession

  included do
    before_action :deny_requester_operational_shell
  end

  private

  def deny_requester_operational_shell
    return unless request.path == '/app' || request.path.start_with?('/app/')
    return if request.path.match?(%r{\A/app/(?:login|auth)(?:/|\z)})
    return unless current_user && current_user.account_users.none?

    response.headers['Cache-Control'] = 'no-store'
    head :forbidden
  end
end
