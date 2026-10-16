# Reads use the same personal native SIP-to-user association as the legacy history.
class Pabx::Access
  def initialize(account:, user:)
    @account = account
    @user = user
  end

  def records
    integration = @account.telephony_integration
    credential = @account.sip_credentials.find_by!(user: @user)
    settings = Pabx::Settings.new(integration) if integration
    raise Pabx::Error, 'HISTORY_DISABLED' unless settings&.enabled? && credential.configured?
    raise ActiveRecord::RecordNotFound unless @account.users.exists?(id: @user.id)
    state = integration.pabx_sync_state
    if state['last_error'] == 'TENANT_MISMATCH' || state.dig('diagnostic', 'tenant_compatible') == false
      raise Pabx::Error, 'TENANT_MISMATCH'
    end

    TelephonyCallRecord.where(account: @account, provider: Pabx::Settings::PROVIDER,
                             external_tenant: settings.data.fetch('expected_tenant').to_s, extension: credential.history_extension)
  end
end
