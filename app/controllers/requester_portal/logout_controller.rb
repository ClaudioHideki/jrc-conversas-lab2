# frozen_string_literal: true

class RequesterPortal::LogoutController < DeviseOverrides::SessionsController
  include RequesterPortal::NativeSession
  protect_from_forgery with: :exception, prepend: true

  def destroy
    super
  ensure
    cookies.delete(RequesterPortal::NativeSession::COOKIE, path: '/')
    RequesterPortal::NativeSession::HEADERS.each { |key| response.headers.delete(key) }
    response.headers['Cache-Control'] = 'no-store'
  end
end
