class Api::V1::Accounts::Crm::SignatureIntegrationsController < Api::V1::Accounts::Crm::BaseController
  rescue_from JrcBackoffice::Docusign::Error do |error|
    render json: { code: error.code }, status: :unprocessable_entity
  end
  rescue_from JrcBackoffice::SignatureConfiguration::Changed do
    render json: { code: 'CONFIGURATION_CHANGED' }, status: :conflict
  end

  def show
    render json: present(configuration.current)
  end

  def update
    record = configuration.save!(attributes: integration_params.to_h, expected_revision: params.require(:revision))
    render json: present(record)
  end

  def check
    render json: present(configuration.check!(expected_revision: params.require(:revision)))
  end

  private

  def configuration
    @configuration ||= JrcBackoffice::SignatureConfiguration.new(account: crm_scope, actor: Current.user)
  end

  def present(record)
    can_manage = JrcBackoffice::SignatureConfiguration.can_manage?(account: crm_scope, actor: Current.user)
    data = record&.serializable_hash || { 'provider' => 'DocuSign', 'configured' => false, 'delivery_ready' => false }
    return data.merge('can_manage' => false) unless can_manage

    data.merge('can_manage' => true, 'revision' => record&.revision || 0,
               'connect_url' => record && connect_url(record),
               'details' => record&.attributes&.slice(*JrcBackoffice::SignatureConfiguration::FIELDS))
  end

  def connect_url(record)
    origin = URI.parse(ENV.fetch('FRONTEND_URL', ''))
    return unless origin.scheme == 'https' && origin.host.present? && !origin.userinfo && !origin.query && !origin.fragment

    origin.path = "/webhooks/docusign/#{record.public_id}"
    origin.to_s
  rescue URI::InvalidURIError
    nil
  end

  def integration_params
    params.require(:integration).permit(:environment, :integration_key, :impersonated_user_id, :external_account_id,
                                        :enabled, :private_key, connect_hmac_keys: [])
  end
end
