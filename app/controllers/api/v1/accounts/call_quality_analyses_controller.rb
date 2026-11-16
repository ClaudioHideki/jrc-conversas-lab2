class Api::V1::Accounts::CallQualityAnalysesController < Api::V1::Accounts::BaseController
  MAX_LOOKUP_DAYS = 31

  def index
    JrcContactCenter::RecordingAccess.authorize!(account: Current.account, user: Current.user, action: :view)
    call = find_call_from_hodupbx!
    analysis = JrcVoiceQuality::SupabaseClient.new.find_analysis(
      account_id: Current.account.id,
      call_id: JrcVoiceQuality.call_id_for(call)
    )

    return render json: { analyzed: false, analysis: nil } unless analysis

    render json: { analyzed: true, analysis: analysis }
  rescue JrcVoiceQuality::Error => e
    render_error(e)
  rescue Hodupbx::CallHistoryService::Error => e
    render json: { error: e.code, message: 'Nao foi possivel validar a chamada no PABX.' }, status: :bad_gateway
  end

  def create
    JrcContactCenter::RecordingAccess.authorize!(account: Current.account, user: Current.user, action: :listen)
    credential = current_credential!
    call = find_call_from_hodupbx!(credential)
    result = JrcVoiceQuality::Processor.new(
      account: Current.account,
      user: Current.user,
      credential: credential,
      call: call
    ).call

    render json: result
  rescue JrcVoiceQuality::Error => e
    render_error(e)
  rescue Hodupbx::CallHistoryService::Error => e
    render json: { error: e.code, message: 'Nao foi possivel validar a chamada no PABX.' }, status: :bad_gateway
  end

  private

  def current_credential!
    credential = Current.account.sip_credentials.find_by(user: Current.user)
    return credential if credential&.configured?

    raise JrcVoiceQuality::ConfigurationError.new('Ramal do usuario nao configurado.', code: :configuration_missing)
  end

  def find_call_from_hodupbx!(credential = current_credential!)
    integration = Current.account.telephony_integration
    raise JrcVoiceQuality::ConfigurationError.new('Historico de chamadas nao configurado para a conta.', code: :configuration_missing) unless integration

    start_date, end_date = lookup_dates(integration)
    result = Hodupbx::CallHistoryService.new(
      integration: integration,
      extension: credential.history_extension,
      start_date: start_date,
      end_date: end_date
    ).call

    call_id = call_params[:unique_id].presence || call_params[:id].presence
    call = result[:calls].find { |record| record[:unique_id].to_s == call_id.to_s || record[:id].to_s == call_id.to_s }
    raise JrcVoiceQuality::RecordingError.new('Chamada nao encontrada no historico do usuario.', code: :call_not_found) unless call

    call
  end

  def lookup_dates(integration)
    if call_params[:started_at].present?
      date = Time.zone.parse(call_params[:started_at]).to_date
      return [date, date]
    end

    end_date = call_params[:end_date].present? ? Date.iso8601(call_params[:end_date]) : Time.zone.today
    start_date = call_params[:start_date].present? ? Date.iso8601(call_params[:start_date]) : end_date - (integration.default_period_days - 1).days
    raise JrcVoiceQuality::RecordingError.new('Periodo invalido.', code: :invalid_period) if start_date > end_date || (end_date - start_date).to_i >= MAX_LOOKUP_DAYS

    [start_date, end_date]
  rescue ArgumentError, TypeError
    raise JrcVoiceQuality::RecordingError.new('Periodo invalido.', code: :invalid_period)
  end

  def call_params
    @call_params ||= params.fetch(:call, params).permit(:id, :unique_id, :started_at, :start_date, :end_date)
  end

  def render_error(error)
    render json: { error: error.code, message: error.message }, status: status_for(error.code)
  end

  def status_for(code)
    return :not_found if code == :call_not_found
    return :conflict if code == :already_analyzed
    return :gateway_timeout if %i[recording_timeout timeout].include?(code)
    return :bad_gateway if %i[recording_unavailable transcription_failed analysis_failed supabase_error].include?(code)
    return :forbidden if code == :unsafe_recording_url

    :unprocessable_entity
  end
end
