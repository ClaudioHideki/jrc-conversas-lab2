class JrcVoiceQuality::SupabaseClient
  REQUEST_TIMEOUT = 20
  ANALYSIS_FIELDS = %w[
    resumo_conversa sentimento_cliente sentimento_atendente temperatura_conversa tom_cliente tom_atendente risco_churn
    risco_reclamacao classificacao_ligacao status_monitoria confianca_transcricao observacao_transcricao
  ].freeze
  ANALYSIS_FLAGS = %w[
    houve_agressividade_cliente houve_agressividade_atendente houve_empatia houve_cordialidade houve_interrupcao
    cliente_demonstrou_insatisfacao cliente_ameacou_cancelar cliente_mencionou_procon_anatel cliente_mencionou_processo
    problema_resolvido necessita_retorno alerta_supervisao
  ].freeze

  # A legacy schema without Account columns is unavailable, never an excuse
  # to retry a query without its tenant predicate.
  SUMMARY_FIELDS = %w[
    account_id
    analise_id
    chamada_id
    call_id
    arquivo_audio
    telefone_origem
    ramal
    agente
    data_chamada
    status_chamada
    texto_transcrito
    modelo_transcricao
    resumo_conversa
    sentimento_cliente
    sentimento_atendente
    temperatura_conversa
    risco_churn
    risco_reclamacao
    nota_final
    classificacao_ligacao
    status_monitoria
    alerta_supervisao
    motivo_alerta
    confianca_transcricao
    observacao_transcricao
    payload_completo
    analise_criada_em
  ].freeze

  def configured?
    supabase_url.present? && service_role_key.present?
  end

  def find_analyses_by_call_ids(account_id:, call_ids:)
    return {} if call_ids.blank? || !configured?

    rows = request(
      :get,
      '/vw_qualidade_pabx_dashboard',
      query: {
        select: SUMMARY_FIELDS.join(','),
        account_id: "eq.#{scope_id!(account_id)}",
        call_id: "in.(#{postgrest_list(call_ids)})",
        order: 'analise_criada_em.desc'
      }
    )

    Array(rows).each_with_object({}) do |row, memo|
      verify_analysis_row!(row, account_id, call_ids)
      memo[row['call_id']] ||= summary_payload(row)
    end
  rescue JrcVoiceQuality::PersistenceError => e
    raise if e.code == :scope_unverified

    Rails.logger.warn("[JRC Voice Quality] Supabase indisponivel ao buscar analises: #{e.message}")
    {}
  end

  def find_analysis(account_id:, call_id:)
    return if call_id.blank?

    raise_configuration! unless configured?

    rows = request(
      :get,
      '/vw_qualidade_pabx_dashboard',
      query: {
        select: SUMMARY_FIELDS.join(','),
        account_id: "eq.#{scope_id!(account_id)}",
        call_id: "eq.#{resource_id!(call_id)}",
        order: 'analise_criada_em.desc',
        limit: 1
      }
    )

    row = Array(rows).first
    verify_row!(row, account_id) if row
    raise JrcVoiceQuality::PersistenceError.new('Chamada fora da consulta.', code: :scope_unverified) if row && row['call_id'].to_s != call_id.to_s

    row ? summary_payload(row) : nil
  end

  def upsert_call!(metadata)
    raise_configuration! unless configured?
    attributes = metadata.to_h.stringify_keys
    account_id = scope_id!(attributes.fetch('account_id'))
    call_id = resource_id!(attributes.fetch('call_id'))
    query = { select: 'id,account_id,call_id', account_id: "eq.#{account_id}", call_id: "eq.#{call_id}", limit: 1 }
    existing = request(:get, '/chamadas_pabx', query: query).first
    if existing
      verify_row!(existing, account_id)
      return existing
    end

    response = request(:post, '/chamadas_pabx', body: attributes.merge('account_id' => account_id), headers: { 'Prefer' => 'return=representation' })
    row = Array(response).first
    raise JrcVoiceQuality::PersistenceError.new('Chamada nao persistida.', code: :supabase_error) unless row

    verify_row!(row, account_id)
    row
  end

  def save_transcription!(account_id:, chamada_id:, text:, model:)
    verify_call!(account_id, chamada_id)
    request(
      :post,
      '/transcricoes_pabx',
      body: {
        account_id: scope_id!(account_id),
        chamada_id: chamada_id,
        texto_transcrito: text,
        modelo_transcricao: model
      },
      headers: { 'Prefer' => 'return=minimal' }
    )
  end

  def save_analysis!(account_id:, chamada_id:, analysis:)
    verify_call!(account_id, chamada_id)
    av = analysis.fetch('avaliacao_atendente', {})

    request(
      :post,
      '/analises_qualidade_pabx',
      body: {
        account_id: scope_id!(account_id),
        chamada_id: chamada_id,
        **analysis_fields(analysis),
        **analysis_flags(analysis),
        assuntos_abordados: array_value(analysis['assuntos_abordados']),
        cordialidade: bounded_integer(av['cordialidade'], 0, 10),
        empatia: bounded_integer(av['empatia'], 0, 10),
        clareza_comunicacao: bounded_integer(av['clareza_comunicacao'], 0, 10),
        dominio_assunto: bounded_integer(av['dominio_assunto'], 0, 10),
        conducao_conversa: bounded_integer(av['conducao_conversa'], 0, 10),
        resolucao_problema: bounded_integer(av['resolucao_problema'], 0, 15),
        cumprimento_protocolo: bounded_integer(av['cumprimento_protocolo'], 0, 10),
        controle_emocional: bounded_integer(av['controle_emocional'], 0, 10),
        experiencia_cliente: bounded_integer(av['experiencia_cliente'], 0, 15),
        nota_final: bounded_integer(
          av['nota_final'] || analysis['nota_final'],
          0,
          100
        ),
        pontos_positivos: array_value(analysis['pontos_positivos']),
        pontos_negativos: array_value(analysis['pontos_negativos']),
        oportunidades_melhoria: array_value(analysis['oportunidades_melhoria']),
        treinamento_recomendado: array_value(analysis['treinamento_recomendado']),
        motivo_alerta: analysis['motivo_alerta'].to_s,
        payload_completo: analysis
      },
      headers: { 'Prefer' => 'return=minimal' }
    )
  end

  def update_call_status!(account_id:, chamada_id:, status:)
    verify_call!(account_id, chamada_id)
    request(
      :patch,
      '/chamadas_pabx',
      query: {
        account_id: "eq.#{scope_id!(account_id)}",
        id: "eq.#{chamada_id}"
      },
      body: { status: status },
      headers: { 'Prefer' => 'return=minimal' }
    )
  rescue JrcVoiceQuality::PersistenceError => e
    raise if e.code == :scope_unverified

    Rails.logger.warn(
      "[JRC Voice Quality] Falha ao atualizar status no Supabase: #{e.message}"
    )
  end

  private

  def analysis_fields(analysis)
    ANALYSIS_FIELDS.index_with { |field| analysis[field] }.symbolize_keys
  end

  def analysis_flags(analysis)
    ANALYSIS_FLAGS.index_with { |field| truthy?(analysis[field]) }.symbolize_keys
  end

  def resource_id!(value)
    valid = value.is_a?(String) || value.is_a?(Integer)
    unless valid && value.to_s.match?(/\A[0-9A-Za-z_.:-]{1,255}\z/)
      raise JrcVoiceQuality::PersistenceError.new('Identificador de qualidade invalido.', code: :scope_unverified)
    end

    value.to_s
  end

  def scope_id!(value)
    raise JrcVoiceQuality::PersistenceError.new('Conta de qualidade invalida.', code: :scope_unverified) unless value.to_s.match?(/\A[1-9]\d*\z/)

    value.to_i
  end

  def verify_row!(row, account_id)
    valid = row.is_a?(Hash) && row['account_id'].to_s == scope_id!(account_id).to_s
    raise JrcVoiceQuality::PersistenceError.new('Escopo de qualidade nao confirmado.', code: :scope_unverified) unless valid
  end

  def verify_analysis_row!(row, account_id, call_ids)
    verify_row!(row, account_id)
    return if call_ids.map(&:to_s).include?(row['call_id'].to_s)

    raise JrcVoiceQuality::PersistenceError.new('Chamada fora da consulta.', code: :scope_unverified)
  end

  def verify_call!(account_id, chamada_id)
    query = { select: 'id,account_id', id: "eq.#{resource_id!(chamada_id)}", account_id: "eq.#{scope_id!(account_id)}", limit: 1 }
    rows = request(:get, '/chamadas_pabx', query: query)
    verify_row!(Array(rows).first, account_id)
  end

  def supabase_url
    ENV.fetch('SUPABASE_URL', '').to_s.delete_suffix('/')
  end

  def service_role_key
    ENV.fetch('SUPABASE_SERVICE_ROLE_KEY', '').to_s
  end

  def rest_url
    "#{supabase_url}/rest/v1"
  end

  def raise_configuration!
    raise JrcVoiceQuality::ConfigurationError.new(
      'Supabase nao configurado. Defina SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY.',
      code: :supabase_not_configured
    )
  end

  def request_options(values)
    raise ArgumentError, 'Unknown Supabase request options' unless (values.keys - %i[query body headers timeout]).empty?

    { query: values.fetch(:query, {}), body: values[:body]&.to_json,
      headers: default_headers.merge(values.fetch(:headers, {})), timeout: values.fetch(:timeout, REQUEST_TIMEOUT) }
  end

  def request(method, path, **options)
    response = HTTParty.public_send(method, "#{rest_url}#{path}", **request_options(options))

    return parse_response(response) if response.success?

    raise JrcVoiceQuality::PersistenceError.new(
      "Supabase retornou HTTP #{response.code}.",
      code: :supabase_error
    )
  rescue HTTParty::Error,
         SocketError,
         Errno::ECONNREFUSED,
         Net::OpenTimeout,
         Net::ReadTimeout => e
    raise JrcVoiceQuality::PersistenceError.new(
      "Falha ao conectar no Supabase (#{e.class.name}).",
      code: :supabase_error
    )
  end

  def parse_response(response)
    return [] if response.body.blank?

    JSON.parse(response.body)
  rescue JSON::ParserError
    raise JrcVoiceQuality::PersistenceError.new(
      'Supabase retornou JSON invalido',
      code: :supabase_error
    )
  end

  def default_headers
    {
      'apikey' => service_role_key,
      'Authorization' => "Bearer #{service_role_key}",
      'Content-Type' => 'application/json',
      'Accept' => 'application/json',

      # Evita resposta gzip que esta versao do HTTParty
      # estava entregando sem descompactar.
      'Accept-Encoding' => 'identity'
    }
  end

  def postgrest_list(values)
    Array(values)
      .compact
      .uniq
      .map { |value| %("#{resource_id!(value)}") }
      .join(',')
  end

  def summary_payload(row)
    payload =
      row['payload_completo'].is_a?(Hash) ? row['payload_completo'] : {}

    {
      id: row['analise_id'],
      chamada_id: row['chamada_id'],
      call_id: row['call_id'],
      status: row['status_monitoria'],
      nota_final:
        row['nota_final'] ||
        payload.dig('avaliacao_atendente', 'nota_final') ||
        payload['nota_final'],
      classificacao_ligacao: row['classificacao_ligacao'],
      sentimento_cliente: row['sentimento_cliente'],
      sentimento_atendente: row['sentimento_atendente'],
      temperatura_conversa: row['temperatura_conversa'],
      risco_churn: row['risco_churn'],
      risco_reclamacao: row['risco_reclamacao'],
      resumo_conversa: row['resumo_conversa'],
      alerta_supervisao: row['alerta_supervisao'],
      motivo_alerta: row['motivo_alerta'],
      confianca_transcricao: row['confianca_transcricao'],
      observacao_transcricao: row['observacao_transcricao'],
      texto_transcrito: row['texto_transcrito'],
      payload_completo: payload,
      created_at: row['analise_criada_em']
    }
  end

  def array_value(value)
    return value if value.is_a?(Array)
    return [] if value.blank?

    [value]
  end

  def truthy?(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end

  def bounded_integer(value, min, max)
    value.to_i.clamp(min, max)
  end
end
