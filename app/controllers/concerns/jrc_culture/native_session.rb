# frozen_string_literal: true

module JrcCulture::NativeSession
  extend ActiveSupport::Concern
  include RequesterPortal::NativeSession

  COOKIE = '_jrc_culture_portal'

  included do
    protect_from_forgery with: :exception, prepend: true
    after_action :hide_culture_credentials
  end

  private

  def requester_credentials
    cookies.encrypted[COOKIE] || native_dashboard_credentials || {}
  end

  def write_culture_session
    credentials = RequesterPortal::NativeSession::HEADERS.index_with { |name| request.headers[name] }
    cookies.encrypted[COOKIE] = {
      value: credentials, httponly: true, same_site: :lax, secure: request.ssl?, path: '/portal/manual-de-cultura',
      expires: Time.at(credentials.fetch('expiry').to_i)
    }
  end

  def hide_culture_credentials
    RequesterPortal::NativeSession::HEADERS.each { |name| response.headers.delete(name) }
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Referrer-Policy'] = 'same-origin'
    response.headers['X-Frame-Options'] = 'SAMEORIGIN'
  end
end
