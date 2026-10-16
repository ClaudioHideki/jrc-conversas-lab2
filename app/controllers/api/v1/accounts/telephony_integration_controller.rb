class Api::V1::Accounts::TelephonyIntegrationController < Api::V1::Accounts::BaseController
  before_action :ensure_super_admin!

  def show
    render json: Pabx::Settings.new(integration).public_payload
  end

  def update
    row = integration
    raw_settings = params.require(:settings)
    raise Pabx::Error, 'INVALID_SETTINGS' unless raw_settings.is_a?(ActionController::Parameters)

    row.with_lock do
      settings = raw_settings.permit(*Pabx::Settings::KEYS.excluding('cdr_fields'), cdr_fields: Pabx::Settings::CDR_FIELDS).to_h
      row.pabx_settings = settings
      row.pabx_username = params[:api_username] if params[:api_username].present?
      row.pabx_password = params[:api_password] if params[:api_password].present?
      row.pabx_sync_state = {}
      row.save!
    end
    render json: Pabx::Settings.new(row).public_payload
  end

  def test_connection
    row = integration
    fingerprint = Pabx::Settings.new(row).fingerprint
    result = Pabx::Diagnostics.new(row).call
    if row.persisted?
      row.with_lock do
        raise Pabx::Error, 'STALE_CONFIGURATION' unless Pabx::Settings.new(row).fingerprint == fingerprint

        row.update!(pabx_sync_state: row.pabx_sync_state.merge('diagnostic' => result))
      end
    end
    render json: result
  end

  def synchronize
    settings = Pabx::Settings.new(integration)
    raise Pabx::Error, 'SYNC_DISABLED' unless settings.sync_enabled?

    raise Pabx::Error, 'SYNC_PENDING' unless Pabx::ScheduleJob.new.enqueue(integration)
    head :accepted
  end

  private

  def integration
    Current.account.telephony_integration || Current.account.build_telephony_integration
  end

  def ensure_super_admin!
    head :forbidden unless Current.user.is_a?(SuperAdmin)
  end

  rescue_from Pabx::Error do |error|
    render json: { error: error.code, message: 'Não foi possível validar a API PABX. Consulte o diagnóstico.' }, status: :unprocessable_entity
  end
end
