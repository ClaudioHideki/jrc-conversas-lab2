require 'faraday/multipart'

class JrcVoiceQuality::OpenaiClient
  TRANSCRIPTION_MODEL = 'gpt-4o-mini-transcribe'

  def initialize(account:)
    @account = account
  end

  def configured?
    provider.present?
  end

  def transcription_model
    provider.settings['transcription_model'].presence || TRANSCRIPTION_MODEL
  end

  def analysis_model
    provider.default_model
  end

  def transcribe!(tempfile:, filename:, content_type:)
    unless configured?
      raise JrcVoiceQuality::TranscriptionError.new(
        'Provedor de IA da conta nao configurado para transcricao.',
        code: :openai_not_configured
      )
    end

    tempfile.rewind

    response = multipart_connection.post('audio/transcriptions') do |request|
      request.body = {
        model: transcription_model,
        language: 'pt',
        file: Faraday::UploadIO.new(
          tempfile.path,
          content_type.presence || 'audio/mpeg',
          filename
        )
      }
    end

    payload = parse_response(response, :transcription)
    text = payload['text'].to_s.strip

    if text.blank?
      raise JrcVoiceQuality::TranscriptionError.new(
        'A OpenAI nao retornou texto transcrito.',
        code: :transcription_failed
      )
    end

    text
  end

  def analyze!(transcript)
    unless configured?
      raise JrcVoiceQuality::AnalysisError.new(
        'Provedor de IA da conta nao configurado.',
        code: :openai_not_configured
      )
    end

    response = json_connection.post('chat/completions') do |request|
      request.body = {
        model: analysis_model,
        messages: [
          {
            role: 'system',
            content: system_prompt
          },
          {
            role: 'user',
            content: <<~TEXT
              Analise a ligacao abaixo como monitoria de qualidade de call center.

              Transcricao:
              #{transcript}
            TEXT
          }
        ],
        response_format: {
          type: 'json_schema',
          json_schema: {
            name: 'analise_qualidade_pabx',
            strict: true,
            schema: analysis_schema
          }
        }
      }.to_json
    end

    payload = parse_response(response, :analysis)

    content = payload
      .dig('choices', 0, 'message', 'content')
      .to_s

    analysis = JSON.parse(content)

    normalize_analysis(analysis, transcript)
  rescue JSON::ParserError
    raise JrcVoiceQuality::AnalysisError.new(
      'A OpenAI retornou uma analise em JSON invalida.',
      code: :analysis_failed
    )
  end

  private

  def api_key
    provider.api_key
  end

  def base_url
    provider.request_base_url
  end

  def provider
    @provider ||= JrcAi::AccountProvider.resolve(@account)
  rescue JrcNico::RuntimeClient::Error
    nil
  end

  def multipart_connection
    Faraday.new(url: base_url) do |faraday|
      faraday.request :multipart
      faraday.request :url_encoded

      faraday.headers['Authorization'] = "Bearer #{api_key}"

      faraday.options.timeout = 120

      faraday.adapter Faraday.default_adapter
    end
  end

  def json_connection
    Faraday.new(url: base_url) do |faraday|
      faraday.headers['Authorization'] = "Bearer #{api_key}"
      faraday.headers['Content-Type'] = 'application/json'

      faraday.options.timeout = 120

      faraday.adapter Faraday.default_adapter
    end
  end

  def parse_response(response, step)
    return JSON.parse(response.body) if response.success?

    code =
      step == :transcription ? :transcription_failed : :analysis_failed

    error_class =
      if step == :transcription
        JrcVoiceQuality::TranscriptionError
      else
        JrcVoiceQuality::AnalysisError
      end

    raise error_class.new(
      "O provedor de IA recusou a operação (HTTP #{response.status}). Verifique a configuração e a cota da conta.",
      code: code
    )
  end

  def normalize_analysis(analysis, transcript)
    quality =
      JrcVoiceQuality::LocalAnalyzer
      .new(transcript)
      .send(:transcription_quality)

    av = analysis['avaliacao_atendente'] || {}

    score_fields = {
      'cordialidade' => 10,
      'empatia' => 10,
      'clareza_comunicacao' => 10,
      'dominio_assunto' => 10,
      'conducao_conversa' => 10,
      'resolucao_problema' => 15,
      'cumprimento_protocolo' => 10,
      'controle_emocional' => 10,
      'experiencia_cliente' => 15
    }

    score_fields.each do |field, max|
      av[field] = av[field].to_i.clamp(0, max)
    end

    av['nota_final'] =
      score_fields
      .keys
      .sum { |field| av[field].to_i }
      .clamp(0, 100)

    analysis['avaliacao_atendente'] = av
    analysis['nota_final'] = av['nota_final']

    analysis['classificacao_ligacao'] =
      enum_or_default(
        analysis['classificacao_ligacao'],
        %w[excelente boa regular ruim critica],
        classification_from_score(av['nota_final'])
      )

    analysis['status_monitoria'] =
      enum_or_default(
        analysis['status_monitoria'],
        %w[
          aprovada
          aprovada_com_observacao
          reprovada
          critica_para_supervisao
        ],
        status_from_score(av['nota_final'])
      )

    analysis['temperatura_conversa'] =
      enum_or_default(
        analysis['temperatura_conversa'],
        %w[fria neutra quente critica],
        'neutra'
      )

    analysis['risco_churn'] =
      enum_or_default(
        analysis['risco_churn'],
        %w[baixo medio alto critico],
        'baixo'
      )

    analysis['risco_reclamacao'] =
      enum_or_default(
        analysis['risco_reclamacao'],
        %w[baixo medio alto critico],
        'baixo'
      )

    %w[
      assuntos_abordados
      pontos_positivos
      pontos_negativos
      oportunidades_melhoria
      treinamento_recomendado
      trechos_relevantes
    ].each do |field|
      analysis[field] = [] unless analysis[field].is_a?(Array)
    end

    analysis['confianca_transcricao'] = quality[:confidence]
    analysis['observacao_transcricao'] = quality[:note]
    analysis['texto_transcrito'] = transcript

    analysis
  end

  def enum_or_default(value, allowed, fallback)
    allowed.include?(value) ? value : fallback
  end

  def classification_from_score(score)
    return 'excelente' if score >= 90
    return 'boa' if score >= 75
    return 'regular' if score >= 60
    return 'ruim' if score >= 40

    'critica'
  end

  def status_from_score(score)
    return 'aprovada' if score >= 75
    return 'aprovada_com_observacao' if score >= 60
    return 'reprovada' if score >= 40

    'critica_para_supervisao'
  end

  def system_prompt
    <<~PROMPT
      Voce e um agente senior de monitoria de qualidade de call center da JRC.

      Analise a transcricao da ligacao considerando:
      - contexto da conversa;
      - postura do atendente;
      - sentimento e comportamento do cliente;
      - resolucao do problema;
      - riscos operacionais;
      - experiencia do cliente;
      - oportunidades de melhoria.

      Nao invente informacoes.

      Quando algo nao puder ser determinado pela transcricao,
      sinalize a incerteza e nao penalize automaticamente o atendente.

      A avaliacao_atendente deve obrigatoriamente seguir esta escala:

      cordialidade: 0 a 10 pontos
      empatia: 0 a 10 pontos
      clareza_comunicacao: 0 a 10 pontos
      dominio_assunto: 0 a 10 pontos
      conducao_conversa: 0 a 10 pontos
      resolucao_problema: 0 a 15 pontos
      cumprimento_protocolo: 0 a 10 pontos
      controle_emocional: 0 a 10 pontos
      experiencia_cliente: 0 a 15 pontos

      A soma maxima e exatamente 100 pontos.

      Use toda a faixa de pontuacao disponivel.

      Nao trate os criterios como uma escala de 0 a 5.

      Referencia geral da nota final:

      90 a 100 = excelente
      75 a 89 = boa
      60 a 74 = regular
      40 a 59 = ruim
      0 a 39 = critica

      Avalie somente comportamentos que possam ser inferidos da transcricao.

      Nao penalize cumprimento de protocolo quando a transcricao nao fornecer
      elementos suficientes para determinar se havia um protocolo aplicavel.

      A nota deve refletir a qualidade efetiva do atendimento,
      e nao apenas o grau de formalidade da linguagem.

      Linguagem informal, regionalismos ou girias nao devem gerar penalizacao
      por si so quando forem adequados ao contexto e nao prejudicarem
      clareza, respeito ou experiencia do cliente.

      Diferencie conversa informal de atendimento inadequado.

      Considere como pontos positivos:
      - tentativa real de ajudar;
      - cordialidade;
      - empatia;
      - dominio tecnico demonstrado;
      - colaboracao entre as partes;
      - clareza;
      - encaminhamento adequado;
      - resolucao total ou parcial do problema.

      Considere como pontos negativos apenas quando estiverem evidentes:
      - agressividade;
      - desrespeito;
      - falta de interesse;
      - informacao incorreta;
      - abandono do cliente;
      - falta grave de clareza;
      - conducao inadequada;
      - ausencia de tentativa de resolucao.

      Se o problema depender de uma terceira pessoa ou etapa posterior,
      isso nao significa automaticamente falha do atendente.

      O campo nota_final deve representar a soma dos nove criterios.

      Responda somente JSON valido no schema solicitado.
    PROMPT
  end

  def analysis_schema
    {
      type: 'object',
      additionalProperties: false,
      properties: {
        resumo_conversa: {
          type: 'string'
        },

        assuntos_abordados: {
          type: 'array',
          items: {
            type: 'string'
          }
        },

        sentimento_cliente: {
          type: 'string',
          enum: %w[
            positivo
            neutro
            negativo
            critico
            nao_identificado
          ]
        },

        sentimento_atendente: {
          type: 'string',
          enum: %w[
            positivo
            neutro
            negativo
            nao_identificado
          ]
        },

        temperatura_conversa: {
          type: 'string',
          enum: %w[
            fria
            neutra
            quente
            critica
          ]
        },

        tom_cliente: {
          type: 'string'
        },

        tom_atendente: {
          type: 'string'
        },

        houve_agressividade_cliente: {
          type: 'boolean'
        },

        houve_agressividade_atendente: {
          type: 'boolean'
        },

        houve_empatia: {
          type: 'boolean'
        },

        houve_cordialidade: {
          type: 'boolean'
        },

        houve_interrupcao: {
          type: 'boolean'
        },

        cliente_demonstrou_insatisfacao: {
          type: 'boolean'
        },

        cliente_ameacou_cancelar: {
          type: 'boolean'
        },

        cliente_mencionou_procon_anatel: {
          type: 'boolean'
        },

        cliente_mencionou_processo: {
          type: 'boolean'
        },

        problema_resolvido: {
          type: 'boolean'
        },

        necessita_retorno: {
          type: 'boolean'
        },

        risco_churn: {
          type: 'string',
          enum: %w[
            baixo
            medio
            alto
            critico
          ]
        },

        risco_reclamacao: {
          type: 'string',
          enum: %w[
            baixo
            medio
            alto
            critico
          ]
        },

        avaliacao_atendente: {
          type: 'object',
          additionalProperties: false,
          properties: {
            cordialidade: {
              type: 'integer',
              minimum: 0,
              maximum: 10
            },

            empatia: {
              type: 'integer',
              minimum: 0,
              maximum: 10
            },

            clareza_comunicacao: {
              type: 'integer',
              minimum: 0,
              maximum: 10
            },

            dominio_assunto: {
              type: 'integer',
              minimum: 0,
              maximum: 10
            },

            conducao_conversa: {
              type: 'integer',
              minimum: 0,
              maximum: 10
            },

            resolucao_problema: {
              type: 'integer',
              minimum: 0,
              maximum: 15
            },

            cumprimento_protocolo: {
              type: 'integer',
              minimum: 0,
              maximum: 10
            },

            controle_emocional: {
              type: 'integer',
              minimum: 0,
              maximum: 10
            },

            experiencia_cliente: {
              type: 'integer',
              minimum: 0,
              maximum: 15
            },

            nota_final: {
              type: 'integer',
              minimum: 0,
              maximum: 100
            }
          },

          required: %w[
            cordialidade
            empatia
            clareza_comunicacao
            dominio_assunto
            conducao_conversa
            resolucao_problema
            cumprimento_protocolo
            controle_emocional
            experiencia_cliente
            nota_final
          ]
        },

        pontos_positivos: {
          type: 'array',
          items: {
            type: 'string'
          }
        },

        pontos_negativos: {
          type: 'array',
          items: {
            type: 'string'
          }
        },

        oportunidades_melhoria: {
          type: 'array',
          items: {
            type: 'string'
          }
        },

        treinamento_recomendado: {
          type: 'array',
          items: {
            type: 'string'
          }
        },

        classificacao_ligacao: {
          type: 'string',
          enum: %w[
            excelente
            boa
            regular
            ruim
            critica
          ]
        },

        status_monitoria: {
          type: 'string',
          enum: %w[
            aprovada
            aprovada_com_observacao
            reprovada
            critica_para_supervisao
          ]
        },

        alerta_supervisao: {
          type: 'boolean'
        },

        motivo_alerta: {
          type: 'string'
        },

        confianca_transcricao: {
          type: 'string',
          enum: %w[
            alta
            media
            baixa
          ]
        },

        observacao_transcricao: {
          type: 'string'
        },

        confianca_analise: {
          type: 'string',
          enum: %w[
            alta
            media
            baixa
          ]
        }
      },

      required: %w[
        resumo_conversa
        assuntos_abordados
        sentimento_cliente
        sentimento_atendente
        temperatura_conversa
        tom_cliente
        tom_atendente
        houve_agressividade_cliente
        houve_agressividade_atendente
        houve_empatia
        houve_cordialidade
        houve_interrupcao
        cliente_demonstrou_insatisfacao
        cliente_ameacou_cancelar
        cliente_mencionou_procon_anatel
        cliente_mencionou_processo
        problema_resolvido
        necessita_retorno
        risco_churn
        risco_reclamacao
        avaliacao_atendente
        pontos_positivos
        pontos_negativos
        oportunidades_melhoria
        treinamento_recomendado
        classificacao_ligacao
        status_monitoria
        alerta_supervisao
        motivo_alerta
        confianca_transcricao
        observacao_transcricao
        confianca_analise
      ]
    }
  end
end
