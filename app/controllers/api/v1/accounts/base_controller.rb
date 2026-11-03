class Api::V1::Accounts::BaseController < Api::BaseController
  include SwitchLocale
  include EnsureCurrentAccountHelper
  before_action :current_account
  before_action :validate_token_api_access, if: :authenticate_by_access_token?
  around_action :switch_locale_using_account_locale
  around_action :execute_nico_native_command

  private

  def execute_nico_native_command
    unless request.headers.key?('X-JRC-Nico-Command-Id') || request.headers.key?('X-JRC-Nico-Contract')
      return yield
    end

    JrcNico::NativeBrowserCommand.execute(account: Current.account, user: Current.user, request: request) do
      yield
      response.status
    end
  rescue JrcNico::NativeBrowserCommand::Rejected
    render json: { error: 'nico_native_command_forbidden' }, status: :forbidden
  end

  def validate_token_api_access
    return if Current.account.api_and_webhooks_enabled?

    render json: { error: 'API access is not enabled for this account' }, status: :forbidden
  end
end
