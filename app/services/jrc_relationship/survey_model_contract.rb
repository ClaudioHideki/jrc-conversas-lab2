# frozen_string_literal: true

# Pure validation shared by draft publication and versioned configuration.
# Incomplete drafts are allowed; publication is always strict and step-aware.
class JrcRelationship::SurveyModelContract
  ROLES = %w[administrator supervisor agent].freeze
  CHANNELS = %w[whatsapp email public_link].freeze
  EVENTS = %w[closed first_agent_response manual].freeze
  TOP_KEYS = %w[name description kind active unit_id operator_id code questions channels rules permissions settings].freeze
  attr_reader :errors

  def initialize(payload)
    @data = payload
    @errors = []
  end

  def valid?
    @errors.clear
    unless @data.is_a?(Hash) && (@data.keys - TOP_KEYS).empty? && @data.to_json.bytesize <= 100_000
      error(0, 'model', 'Estrutura do modelo inválida.'); return false
    end
    information
    questions
    channels
    rules
    permissions
    @errors.empty?
  end

  def validate!
    return true if valid?

    raise Invalid.new(errors)
  end

  class Invalid < ArgumentError
    attr_reader :details
    def initialize(details)
      @details = details
      super(details.map { |row| row[:message] }.join(' '))
    end
  end

  private

  def error(step, field, message)
    @errors << { step: step, field: field, message: message }
  end

  def integer?(value, range)
    value.is_a?(Integer) && range.cover?(value)
  end

  def text?(value, limit, required: true)
    value.is_a?(String) && value.length <= limit && (!required || !value.strip.empty?)
  end

  def positive_id?(value)
    value.to_s.match?(/\A[1-9]\d{0,17}\z/)
  end

  def boolean?(value)
    value == true || value == false
  end

  def information
    error(0, 'name', 'Informe um nome de até 120 caracteres.') unless text?(@data['name'], 120)
    error(0, 'description', 'A descrição deve ter até 1.000 caracteres.') unless text?(@data['description'], 1000, required: false)
    error(0, 'kind', 'Selecione NPS, CSAT ou CES.') unless %w[nps csat ces].include?(@data['kind'])
    error(0, 'code', 'Use um código de até 32 letras minúsculas, números, _ ou -.') unless @data['code'].to_s.match?(/\A[a-z0-9_-]{1,32}\z/)
    error(0, 'unit_id', 'Selecione uma unidade autorizada.') unless positive_id?(@data['unit_id'])
    error(0, 'operator_id', 'Selecione uma empresa operadora.') unless positive_id?(@data['operator_id'])
    error(0, 'active', 'Informe o estado de ativação.') unless boolean?(@data['active'])
  end

  def questions
    rows = @data['questions']
    unless rows.is_a?(Array) && rows.size.between?(1, 20)
      error(1, 'questions', 'Adicione entre uma e vinte perguntas.'); return
    end
    valid = JrcRelationship::SurveyQuestionSchema.new(rows).valid?
    valid &&= rows.all? { |q| !q.key?('presentation') || (q['presentation'] == 'stars' && q['type'] == 'scale' && q['max'] - q['min'] <= 10) }
    error(1, 'questions', 'Revise textos, códigos, escalas, opções e condições das perguntas.') unless valid
    first = rows.first
    return unless first.is_a?(Hash)

    if first['type'] != 'scale' || first['required'] != true
      error(1, 'questions.0', 'A primeira pergunta deve ser uma escala obrigatória.')
    elsif @data['kind'] == 'nps' && [first['min'], first['max']] != [0, 10]
      error(1, 'questions.0', 'O NPS utiliza obrigatoriamente a escala de 0 a 10.')
    end
    cfg = @data['settings'] || {}
    unless cfg.is_a?(Hash) && (cfg.keys - %w[thank_you ces_direction low_threshold]).empty?
      error(1, 'settings', 'Configuração de resposta inválida.'); return
    end
    error(1, 'thank_you', 'Mensagem de agradecimento muito longa.') if cfg['thank_you'] && !text?(cfg['thank_you'], 1000, required: false)
    if @data['kind'] == 'ces' && !%w[higher_is_better lower_is_better].include?(cfg['ces_direction'])
      error(1, 'ces_direction', 'Selecione a direção da escala CES.')
    end
    threshold = cfg['low_threshold']
    if !threshold.nil? && (!threshold.is_a?(Numeric) || !threshold.finite? || !first['min'].is_a?(Integer) || !first['max'].is_a?(Integer) || !threshold.between?(first['min'], first['max']))
      error(1, 'low_threshold', 'O limite de baixa avaliação deve pertencer à escala principal.')
    end
  end

  def channels
    rows = @data['channels']
    unless rows.is_a?(Hash) && rows.keys.sort == CHANNELS.sort
      error(2, 'channels', 'Configuração dos canais inválida.'); return
    end
    enabled = 0
    rows.each do |key, row|
      unless row.is_a?(Hash) && (row.keys - %w[enabled inbox_id message whatsapp_template]).empty? && boolean?(row['enabled'])
        error(2, key, 'Configuração de canal inválida.'); next
      end
      next unless row['enabled']
      enabled += 1
      error(2, key, 'Selecione uma caixa de entrada autorizada.') if key != 'public_link' && !positive_id?(row['inbox_id'])
      if key != 'public_link' && (!text?(row['message'], 4000) || !row['message'].include?('{{survey_link}}'))
        error(2, key, 'A mensagem precisa conter o link {{survey_link}}.')
      end
      template = row['whatsapp_template']
      if template && (!template.is_a?(Hash) || key != 'whatsapp')
        error(2, key, 'Template WhatsApp inválido.')
      end
    end
    error(2, 'channels', 'Habilite e configure ao menos um canal.') if enabled.zero?
  end

  def rules
    row = @data['rules']
    keys = %w[event delay_minutes frequency_days expires_hours consent_required priority execution_member_id channel_order send_window ticket_type_id queue_id team_id priority_id]
    unless row.is_a?(Hash) && (row.keys - keys).empty?
      error(3, 'rules', 'Regras de envio inválidas.'); return
    end
    error(3, 'event', 'Selecione um evento suportado.') unless EVENTS.include?(row['event'])
    { 'delay_minutes' => 0..52_560, 'frequency_days' => 0..3650, 'expires_hours' => 1..8760, 'priority' => 0..1000 }.each do |key, range|
      error(3, key, 'Informe um número inteiro dentro do limite permitido.') unless integer?(row[key], range)
    end
    error(3, 'consent_required', 'Informe a regra de consentimento.') unless row['consent_required'] == true
    error(3, 'execution_member_id', 'Selecione o executor autorizado da regra.') unless positive_id?(row['execution_member_id'])
    %w[ticket_type_id queue_id team_id priority_id].each do |key|
      error(3, key, 'Filtro de envio inválido.') unless [nil, ''].include?(row[key]) || positive_id?(row[key])
    end
    order = row['channel_order']
    unless order.is_a?(Array) && order.all? { |item| item.is_a?(String) } && order.sort == CHANNELS.sort
      error(3, 'channel_order', 'Defina uma ordem sem canais duplicados.')
    end
    window = row['send_window']
    return if window.nil?
    unless window.is_a?(Hash) && (window.keys - %w[enabled timezone days start end]).empty? && boolean?(window['enabled'])
      error(3, 'send_window', 'Janela de envio inválida.'); return
    end
    return unless window['enabled']
    days = window['days']
    times = %w[start end].map { |key| window[key] }
    valid = days.is_a?(Array) && days.size.between?(1, 7) && days.uniq == days && days.all? { |day| integer?(day, 0..6) }
    valid &&= times.all? { |time| time.is_a?(String) && time.match?(/\A(?:[01]\d|2[0-3]):[0-5]\d\z/) }
    valid &&= times[0] < times[1] if valid
    valid &&= text?(window['timezone'], 80)
    error(3, 'send_window', 'Revise dias, fuso e horário inicial/final. Use uma janela dentro do mesmo dia.') unless valid
  end

  def permissions
    row = @data['permissions']
    keys = %w[team_ids edit_roles publish_roles response_roles report_roles share_relationship share_reports customer_own_response]
    unless row.is_a?(Hash) && (row.keys - keys).empty?
      error(4, 'permissions', 'Permissões inválidas.'); return
    end
    %w[edit_roles publish_roles response_roles report_roles].each do |key|
      values = row[key]
      valid = values.is_a?(Array) && (values - ROLES).empty? && values.uniq == values && values.include?('administrator')
      error(4, key, 'Revise os perfis autorizados; administradores devem ser mantidos.') unless valid
    end
    teams = row['team_ids']
    error(4, 'team_ids', 'Equipes inválidas.') unless teams.is_a?(Array) && teams.size <= 100 && teams.uniq == teams && teams.all? { |id| positive_id?(id) }
    %w[share_relationship share_reports customer_own_response].each do |key|
      error(4, key, 'Informe uma opção válida.') unless boolean?(row[key])
    end
  end
end
