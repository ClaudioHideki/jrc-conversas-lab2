# frozen_string_literal: true

module RequesterPortal::NativeSession
  extend ActiveSupport::Concern

  COOKIE = '_jrc_requester_portal'
  HEADERS = %w[access-token client uid expiry token-type].freeze

  included do
    prepend_before_action :restore_requester_native_session
    skip_after_action :update_auth_header, raise: false
  end

  private

  def restore_requester_native_session
    credentials = requester_credentials
    return if credentials.empty?

    HEADERS.each { |key| request.headers[key] = credentials[key] }
  end

  def native_dashboard_credentials
    value = cookies['cw_d_session_info']
    return if value.blank?

    credentials = JSON.parse(value)
    credentials if credentials.is_a?(Hash)
  rescue JSON::ParserError
    nil
  end

  def requester_credentials
    cookies.encrypted[COOKIE] || native_dashboard_credentials || {}
  end

  def write_requester_session(credentials)
    cookies.encrypted[COOKIE] = {
      value: credentials, httponly: true, same_site: :lax, secure: request.ssl?, path: '/',
      expires: Time.at(credentials.fetch('expiry').to_i)
    }
  end

  def requester_grants
    @requester_grants ||= JrcServiceDesk::PortalGrant.available_for(current_user)
  end

  def requester_grant
    @requester_grant ||= requester_grants.find { |grant| grant.id.to_s == requester_credentials['grant_id'].to_s }
    raise JrcServiceDesk::PortalIdentityRequired unless @requester_grant

    @requester_grant
  end
end
