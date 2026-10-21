class Api::V1::Accounts::SipCredentialsController < Api::V1::Accounts::BaseController
  before_action :ensure_super_admin!, except: :me
  before_action :set_agent, only: [:update, :destroy]

  def index
    credentials = Current.account.sip_credentials.includes(:user).order(:user_id)
    render json: credentials.map { |credential| admin_payload(credential) }
  end

  def me
    credential = Current.account.sip_credentials.find_by(user: Current.user)
    return render json: { configured: false, enabled: false } unless credential
    return render json: disabled_payload(credential) unless credential.configured?

    render json: {
      configured: true,
      contact_center_enabled: Current.account.feature_enabled?('jrc_contact_center'),
      contact_center_acw_pending: JrcContactCenter::Qualification.pending.exists?(account: Current.account, account_user: Current.account_user),
      enabled: credential.enabled?,
      wss_server: credential.wss_server,
      sip_domain: credential.sip_domain,
      extension: credential.extension,
      call_history_extension: credential.history_extension,
      username: credential.username,
      sip_username: credential.sip_username,
      password: credential.password
    }
  end

  def update
    credential = Current.account.sip_credentials.find_or_initialize_by(user: @agent)
    attributes = credential_params.to_h
    attributes.delete('password') if attributes['password'].blank? && credential.persisted?
    credential.assign_attributes(attributes)
    credential.save!

    render json: admin_payload(credential)
  end

  def destroy
    Current.account.sip_credentials.find_by(user: @agent)&.destroy!
    head :no_content
  end

  private

  def ensure_super_admin!
    return if Current.user.is_a?(SuperAdmin)

    render json: { error: 'Acesso exclusivo do Super Admin' }, status: :forbidden
  end

  def set_agent
    @agent = Current.account.users.find(params[:user_id])
  end

  def credential_params
    params.require(:sip_credential).permit(:wss_server, :sip_domain, :extension, :call_history_extension, :username, :password, :enabled)
  end

  def admin_payload(credential)
    {
      user_id: credential.user_id,
      user_name: credential.user.available_name,
      user_email: credential.user.email,
      wss_server: credential.wss_server,
      sip_domain: credential.sip_domain,
      extension: credential.extension,
      call_history_extension: credential.history_extension,
      username: credential.username,
      sip_username: credential.sip_username,
      enabled: credential.enabled?,
      configured: credential.configured?,
      password_configured: credential.password.present?
    }
  end

  def disabled_payload(credential)
    required_values = [
      credential.wss_server,
      credential.sip_domain,
      credential.extension,
      credential.username,
      credential.password
    ]

    {
      configured: required_values.all?(&:present?),
      enabled: credential.enabled?,
      extension: credential.extension,
      call_history_extension: credential.history_extension
    }
  end
end
