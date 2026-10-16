class Api::V1::Accounts::CallHistoryController < Api::V1::Accounts::BaseController
  MAX_PERIOD_DAYS = 31
  MAX_PER_PAGE = 100
  before_action :private_recording_response, only: [:recording, :recording_metadata]

  def show
    integration = Current.account.telephony_integration
    return show_pabx(integration) if integration && Pabx::Settings.new(integration).enabled?

    credential = Current.account.sip_credentials.find_by(user: Current.user)
    return render_error(:configuration_missing, :unprocessable_entity) unless integration && credential&.configured?

    start_date, end_date = date_range(integration)
    result = Hodupbx::CallHistoryService.new(
      integration: integration,
      extension: credential.history_extension,
      start_date: start_date,
      end_date: end_date
    ).call
    calls = with_quality_analyses(apply_filters(result[:calls]))
    render json: paginated_payload(calls, credential.history_extension, start_date, end_date)
  rescue ArgumentError
    render_error(:invalid_period, :unprocessable_entity)
  rescue Hodupbx::CallHistoryService::Error => e
    render_error(e.code, status_for(e.code))
  end

  def recording
    record = Pabx::Access.new(account: Current.account, user: Current.user).records.find(params[:id])
    raise Pabx::Error, 'RECORDING_UNAVAILABLE' unless record.has_recording?

    result = Pabx::Provider.new(Current.account.telephony_integration).recording(record)
    send_data result[:body], type: result[:content_type], filename: "call-#{record.id}.audio", disposition: 'attachment'
  end

  def recording_metadata
    record = Pabx::Access.new(account: Current.account, user: Current.user).records.find(params[:id])
    settings = Pabx::Settings.new(Current.account.telephony_integration)
    render json: { id: record.id, has_recording: record.has_recording?, recording_state: record.recording_state(settings) }
  end

  rescue_from Pabx::Error do |error|
    render json: { error: error.code, message: 'Histórico PABX indisponível. Verifique a configuração e o tenant no diagnóstico.' },
           status: { 'NOT_FOUND' => :not_found, 'RECORDING_UNAVAILABLE' => :not_found, 'FORBIDDEN' => :forbidden,
                     'RECORDING_FORBIDDEN' => :forbidden, 'EXPIRED' => :gone, 'TIMEOUT' => :gateway_timeout }
                     .fetch(error.code, :unprocessable_entity)
  end

  private

  def private_recording_response
    response.headers['Cache-Control'] = 'private, no-store'
    response.headers['Pragma'] = 'no-cache'
    response.headers['X-Content-Type-Options'] = 'nosniff'
  end

  def show_pabx(integration)
    start_date, end_date = date_range(integration)
    records = Pabx::Access.new(account: Current.account, user: Current.user).records
    zone = Time.find_zone!(params[:time_zone].presence || 'UTC')
    records = records.where(started_at: start_date.in_time_zone(zone).beginning_of_day..end_date.in_time_zone(zone).end_of_day)
                     .order(started_at: :desc, id: :desc)
    records = records.where(direction: params[:direction]) if params[:direction].present?
    if params[:status] == 'missed'
      records = records.where(direction: 'inbound', status: 'unanswered')
    elsif params[:status].present?
      records = records.where(status: params[:status])
    end
    page = [params.fetch(:page, 1).to_i, 1].max
    per_page = params.fetch(:per_page, 30).to_i.clamp(1, MAX_PER_PAGE)
    settings = Pabx::Settings.new(integration)
    calls = records.offset((page - 1) * per_page).limit(per_page).map { |record| record.public_payload(settings: settings) }
    render json: { calls: calls, count: records.count, page: page, per_page: per_page,
                   summary: { total: records.count, answered: records.where(status: 'answered').count,
                              unanswered: records.where(status: 'unanswered').count },
                   extension: Current.account.sip_credentials.find_by!(user: Current.user).history_extension,
                   provider: Pabx::Settings::PROVIDER, sync: integration.pabx_sync_state.except('diagnostic'),
                   fetched_at: Time.current.iso8601, start_date: start_date.iso8601, end_date: end_date.iso8601 }
  end

  def date_range(integration)
    end_date = params[:end_date].present? ? Date.iso8601(params[:end_date]) : Time.zone.today
    start_date = params[:start_date].present? ? Date.iso8601(params[:start_date]) : end_date - (integration.default_period_days - 1).days
    raise ArgumentError if start_date > end_date || (end_date - start_date).to_i >= MAX_PERIOD_DAYS

    [start_date, end_date]
  end

  def apply_filters(calls)
    calls = calls.select { |call| call[:direction] == params[:direction] } if params[:direction].present?
    calls = calls.select { |call| call[:status] == params[:status] } if params[:status].present?
    calls
  end

  def with_quality_analyses(calls)
    call_ids = calls.filter_map { |call| JrcVoiceQuality.call_id_for(call) }
    analyses = JrcVoiceQuality::SupabaseClient.new.find_analyses_by_call_ids(account_id: Current.account.id, call_ids: call_ids)

    calls.map do |call|
      call_id = JrcVoiceQuality.call_id_for(call)
      call.merge(quality_analysis: analyses[call_id])
    end
  end

  def paginated_payload(calls, extension, start_date, end_date)
    page = [params.fetch(:page, 1).to_i, 1].max
    per_page = params.fetch(:per_page, 30).to_i.clamp(1, MAX_PER_PAGE)
    offset = (page - 1) * per_page
    {
      count: calls.size,
      summary: {
        total: calls.size,
        answered: calls.count { |call| call[:status] == 'answered' },
        unanswered: calls.count { |call| call[:status] == 'unanswered' }
      },
      calls: calls.slice(offset, per_page) || [],
      page: page,
      per_page: per_page,
      extension: extension,
      start_date: start_date.iso8601,
      end_date: end_date.iso8601,
      fetched_at: Time.current.iso8601
    }
  end

  def render_error(code, status)
    render json: { error: code, message: message_for(code) }, status: status
  end

  def status_for(code)
    return :gateway_timeout if code == :timeout
    return :bad_gateway if %i[unavailable provider_error invalid_response invalid_credentials].include?(code)

    :unprocessable_entity
  end

  def message_for(code)
    {
      configuration_missing: 'O histórico de chamadas ainda não foi configurado para esta conta.',
      history_disabled: 'O histórico de chamadas está desativado para esta conta.',
      invalid_period: 'O período informado é inválido.',
      invalid_credentials: 'A API do PABX rejeitou as credenciais configuradas.',
      timeout: 'A consulta ao PABX excedeu o tempo limite.',
      invalid_response: 'O PABX retornou uma resposta inválida.'
    }.fetch(code, 'Não foi possível consultar o PABX. Tente novamente.')
  end
end
