# frozen_string_literal: true

# This bridge accepts only credentials ALREADY authenticated by native /auth.
# It has no password, recovery, invitation, MFA or token-generation implementation.
class RequesterPortal::SessionsController < ApplicationController
  include RequesterPortal::NativeSession
  wrap_parameters false

  skip_before_action :restore_requester_native_session, only: :create
  protect_from_forgery with: :exception, prepend: true
  before_action :authenticate_user!
  after_action :hide_native_credentials
  rescue_from ArgumentError, KeyError, with: :invalid_input

  def create
    JrcServiceDesk::Input.attributes(request.request_parameters, [])
    return render json: { code: 'portal_access_denied' }, status: :forbidden if requester_grants.empty?

    credentials = RequesterPortal::NativeSession::HEADERS.index_with { |key| request.headers[key] }
    credentials['grant_id'] = requester_grants.sole.id.to_s if requester_grants.one?
    write_requester_session(credentials)
    render json: { contexts: requester_grants.map(&:public_context), context: requester_grants.one? ? requester_grants.sole.public_context : nil }
  end

  def show
    return render json: { code: 'portal_access_denied' }, status: :forbidden if requester_grants.empty?

    render json: { contexts: requester_grants.map(&:public_context),
                   context: requester_grants.find { |grant| grant.id.to_s == requester_credentials['grant_id'].to_s }&.public_context }
  end

  def update
    values = JrcServiceDesk::Input.attributes(request.request_parameters, %w[context_id])
    grant = requester_grants.find { |row| row.id.to_s == values.fetch('context_id').to_s }
    return render json: { code: 'portal_access_denied' }, status: :forbidden unless grant

    write_requester_session(requester_credentials.merge('grant_id' => grant.id.to_s))
    render json: { contexts: requester_grants.map(&:public_context), context: grant.public_context }
  end

  private

  def hide_native_credentials
    RequesterPortal::NativeSession::HEADERS.each { |key| response.headers.delete(key) }
    response.headers['Cache-Control'] = 'no-store'
  end

  def invalid_input
    render json: { code: 'invalid_input' }, status: :unprocessable_entity
  end
end
