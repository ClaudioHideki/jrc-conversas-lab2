# frozen_string_literal: true

class RequesterPortal::ShellController < ActionController::Base
  include DeviseTokenAuth::Concerns::SetUserByToken
  include RequesterPortal::NativeSession
  include SwitchLocale

  before_action :no_cache
  before_action :authorize_private_shell, unless: -> { request.path == '/portal/login' }
  around_action :switch_locale

  def show
    render layout: false
  end

  private

  def locale_from_user
    current_user&.ui_settings&.dig('locale')
  end

  def authorize_private_shell
    return redirect_to '/portal/login' unless current_user
    return if requester_grants.any?

    head :forbidden
  end

  def no_cache
    response.headers['Cache-Control'] = 'no-store'
    response.headers['Referrer-Policy'] = 'same-origin'
    response.headers['X-Frame-Options'] = 'DENY'
  end
end
