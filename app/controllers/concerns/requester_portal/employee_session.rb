# frozen_string_literal: true

# The bridge accepts only a native authenticated employee; no new login tokens.
module RequesterPortal::EmployeeSession
  extend ActiveSupport::Concern
  include RequesterPortal::NativeSession

  included do
    protect_from_forgery with: :exception, prepend: true
    before_action :require_registered_employee!
    after_action :hide_employee_credentials
  end

  private

  def pundit_user
    super.merge(employee_portal: true)
  end

  def require_registered_employee!
    context = JrcServiceDesk::OperationalContext.new(pundit_user)
    raise Pundit::NotAuthorizedError unless Current.account.internal_attributes['requester_portal_enabled'] == true && JrcServiceDesk::EmployeeAccess.registered?(context)
  end

  def hide_employee_credentials
    RequesterPortal::NativeSession::HEADERS.each { |key| response.headers.delete(key) }
    response.headers['Cache-Control'] = 'no-store'
  end
end
