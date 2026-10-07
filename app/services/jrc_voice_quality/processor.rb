class JrcVoiceQuality::Processor
  MAX_AUDIO_BYTES = 25.megabytes
  AUDIO_CONTENT_TYPE_PREFIXES = %w[audio/ video/ application/octet-stream].freeze
  AUDIO_CONTENT_TYPES = %w[application/x-wav].freeze

  def initialize(account:, user:, credential:, call:)
    @account = account
    @user = user
    @credential = credential
    @call = call.deep_symbolize_keys
    @supabase = JrcVoiceQuality::SupabaseClient.new
    @openai = JrcVoiceQuality::OpenaiClient.new(account: account)
  end

  def call
    validate_call!
    existing = @supabase.find_analysis(account_id: @account.id, call_id: call_id)
    return { status: 'analyzed', already_analyzed: true, analysis: existing } if existing

    registered_call = @supabase.upsert_call!(
     call_metadata.merge(status: 'processando')
    )
    @registered_call_id = registered_call['id']

    result = nil
    SafeFetch.fetch(
      @call[:recording_url],
      max_bytes: MAX_AUDIO_BYTES,
      open_timeout: 5,
      read_timeout: 60,
      allowed_content_type_prefixes: AUDIO_CONTENT_TYPE_PREFIXES,
      allowed_content_types: AUDIO_CONTENT_TYPES
    ) do |download|
      transcript = @openai.transcribe!(
        tempfile: download.tempfile,
        filename: download.filename,
        content_type: download.content_type
      )
      @supabase.save_transcription!(account_id: @account.id, chamada_id: registered_call['id'], text: transcript, model: @openai.transcription_model)

      analysis, mode = analyze(transcript)
      @supabase.save_analysis!(account_id: @account.id, chamada_id: registered_call['id'], analysis: analysis)
      @supabase.update_call_status!(chamada_id: registered_call['id'], status: 'concluido')
      result = {
        status: 'analyzed',
        already_analyzed: false,
        mode: mode,
        call_id: call_id,
        chamada_id: registered_call['id'],
        analysis: response_payload(analysis, registered_call['id'])
      }
    end

    result
  rescue SafeFetch::InvalidUrlError
    raise JrcVoiceQuality::RecordingError.new('URL da gravacao invalida.', code: :invalid_recording_url)
  rescue SafeFetch::UnsafeUrlError
    raise JrcVoiceQuality::RecordingError.new('URL da gravacao bloqueada por seguranca.', code: :unsafe_recording_url)
  rescue SafeFetch::HttpError
    raise JrcVoiceQuality::RecordingError.new('Gravacao indisponivel no PABX.', code: :recording_unavailable)
  rescue SafeFetch::FileTooLargeError
    raise JrcVoiceQuality::RecordingError.new('Gravacao excede o tamanho maximo permitido.', code: :recording_too_large)
  rescue SafeFetch::UnsupportedContentTypeError
    raise JrcVoiceQuality::RecordingError.new('Formato de audio nao suportado.', code: :unsupported_audio)
  rescue SafeFetch::FetchError
    raise JrcVoiceQuality::RecordingError.new('Tempo limite ou falha ao baixar a gravacao.', code: :recording_timeout)
  rescue JrcVoiceQuality::Error => e
    update_error_status
    raise e
  end

  private

  def validate_call!
    raise JrcVoiceQuality::RecordingError.new('Chamada sem identificador.', code: :missing_call_id) if call_id.blank?
    raise JrcVoiceQuality::RecordingError.new('Chamada sem recording_url.', code: :missing_recording_url) if @call[:recording_url].blank?
    raise JrcVoiceQuality::RecordingError.new('URL da gravacao invalida.', code: :invalid_recording_url) unless recording_uri.is_a?(URI::HTTP)
    raise JrcVoiceQuality::ConfigurationError.new('Supabase nao configurado.', code: :supabase_not_configured) unless @supabase.configured?

    unless @openai.configured?
      raise JrcVoiceQuality::TranscriptionError.new('Configure o provedor de IA desta conta para transcricao e monitoria.',
                                                    code: :openai_not_configured)
    end
  rescue URI::InvalidURIError
    raise JrcVoiceQuality::RecordingError.new('URL da gravacao invalida.', code: :invalid_recording_url)
  end

  def analyze(transcript)
    [@openai.analyze!(transcript), 'openai']
  rescue JrcVoiceQuality::AnalysisError => e
    Rails.logger.warn("[JRC Voice Quality] Falha na analise OpenAI; usando motor local: #{e.message}")
    [JrcVoiceQuality::LocalAnalyzer.new(transcript).call, 'open_source_local_fallback']
  end

  def update_error_status
    return if @registered_call_id.blank?

    @supabase.update_call_status!(chamada_id: @registered_call_id, status: 'erro')
  end

  def call_id
    @call_id ||= JrcVoiceQuality.call_id_for(@call)
  end

  def call_metadata
    {
      account_id: @account.id,
      user_id: @user.id,
      call_id: call_id,
      arquivo_audio: File.basename(recording_uri.path.presence || "#{call_id}.audio"),
      telefone_origem: @call.dig(:caller, :number) || @call[:external_number],
      telefone_destino: @call.dig(:callee, :number),
      ramal: @credential.history_extension,
      agente: @user.available_name,
      direction: @call[:direction],
      duracao_segundos: @call[:talk_duration_seconds] || @call[:total_duration_seconds],
      recording_url: @call[:recording_url],
      data_chamada: @call[:started_at] || Time.current.iso8601
    }
  end

  def recording_uri
    @recording_uri ||= URI.parse(@call[:recording_url])
  end

  def response_payload(analysis, chamada_id)
    {
      chamada_id: chamada_id,
      call_id: call_id,
      status: analysis['status_monitoria'],
      nota_final: analysis.dig('avaliacao_atendente', 'nota_final') || analysis['nota_final'],
      classificacao_ligacao: analysis['classificacao_ligacao'],
      sentimento_cliente: analysis['sentimento_cliente'],
      sentimento_atendente: analysis['sentimento_atendente'],
      temperatura_conversa: analysis['temperatura_conversa'],
      risco_churn: analysis['risco_churn'],
      risco_reclamacao: analysis['risco_reclamacao'],
      resumo_conversa: analysis['resumo_conversa'],
      alerta_supervisao: analysis['alerta_supervisao'],
      motivo_alerta: analysis['motivo_alerta'],
      confianca_transcricao: analysis['confianca_transcricao'],
      observacao_transcricao: analysis['observacao_transcricao'],
      texto_transcrito: analysis['texto_transcrito'],
      payload_completo: analysis,
      created_at: Time.current.iso8601
    }
  end
end
