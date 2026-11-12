# frozen_string_literal: true

# The screen and all file formats share OperationalReportQuery/Metrics and the
# native Presenter. No private notes, raw snapshots, attachments or messages.
class JrcServiceDesk::ReportExportData
  COLUMNS = {
    number: 'Protocolo', title: 'Título', company: 'Cliente / empresa', requester: 'Solicitante', unit: 'Unidade',
    service: 'Serviço', category: 'Categoria', priority: 'Prioridade', status: 'Status', queue: 'Fila', team: 'Equipe',
    assignee: 'Responsável atual', opened_at: 'Abertura', updated_at: 'Última atualização', sla_state: 'Situação SLA',
    sla_due_at: 'Limite SLA resolução', resolved_at: 'Resolução', resolution_seconds: 'Tempo de resolução (s)',
    id: 'ID interno', description: 'Descrição resumida', email: 'E-mail autorizado', phone: 'Telefone autorizado',
    contact_id: 'Contato vinculado', subcategory: 'Subcategoria', catalogue_item: 'Item do catálogo', reason: 'Motivo',
    impact: 'Impacto', urgency: 'Urgência', source: 'Canal de abertura', conversation_ids: 'Conversas autorizadas (IDs)',
    resolver: 'Executor da resolução', creator: 'Criador', first_response_at: 'Primeira resposta', attendance_at: 'Início do atendimento',
    closed_at: 'Encerramento', first_response_budget: 'Meta primeira resposta (s)', attendance_budget: 'Meta atendimento (s)',
    resolution_budget: 'Meta resolução (s)', first_response_result: 'Resultado primeira resposta', attendance_result: 'Resultado atendimento',
    resolution_result: 'Resultado resolução', first_response_seconds: 'Tempo primeira resposta (s)', attendance_seconds: 'Tempo atendimento (s)',
    total_seconds: 'Tempo total até encerramento (s)', business_seconds: 'Tempo útil de resolução medido (s)',
    pause_count: 'Quantidade de pausas', pause_reasons: 'Motivos de pausa', paused_seconds: 'Tempo pausado observado (s)',
    reopen_count: 'Reaberturas', last_reopened_at: 'Última reabertura', csat: 'CSAT', nps: 'NPS', ces: 'CES',
    survey_responded_at: 'Resposta à pesquisa', survey_comment: 'Comentário autorizado da pesquisa'
  }.freeze
  SUMMARY_KEYS = COLUMNS.keys.first(18).freeze
  CUSTOMER_KEYS = %i[company requester email phone contact_id csat nps ces survey_responded_at survey_comment].freeze
  SLA_KEYS = %i[sla_state sla_due_at resolution_seconds first_response_at attendance_at first_response_budget attendance_budget resolution_budget
                first_response_result attendance_result resolution_result first_response_seconds attendance_seconds business_seconds].freeze
  HISTORY_KEYS = %i[resolver creator resolved_at closed_at total_seconds pause_count pause_reasons paused_seconds reopen_count
                    last_reopened_at].freeze
  PHASE_LABELS = { 'open' => 'Abertos / em atendimento', 'waiting' => 'Aguardando', 'resolved' => 'Resolvidos',
                   'closed' => 'Encerrados', 'cancelled' => 'Cancelados' }.freeze
  CLOCK_LABELS = { first_response: 'Primeira resposta', attendance: 'Início do atendimento', resolution: 'Resolução' }.freeze
  SLA_LABELS = { observed: 'Medições disponíveis', completed: 'Medições concluídas', mean_elapsed_seconds: 'Tempo médio (s)',
                 completed_breached: 'Concluídos fora do prazo', running_overdue: 'Vencidos em andamento',
                 running_near_due: 'Em risco em andamento', unmeasured_tickets: 'Chamados sem medição' }.freeze
  attr_reader :query, :observed_at, :timezone, :extra
  attr_accessor :collect_details

  def initialize(query)
    @query = query
    @observed_at = Time.current
    @timezone = (Time.find_zone(query.context.account.reporting_timezone) || Time.zone).tzinfo.name
    @extra = { 'SLA' => [], 'OLA' => [], 'Pausas' => [], 'Reaberturas' => [], 'Satisfação' => [] }
  end

  def count
    query.relation.count
  end

  def metrics
    @metrics ||= JrcServiceDesk::OperationalReportMetrics.new(query).call
  end

  def columns(format)
    keys = format == 'csv_summary' ? SUMMARY_KEYS : COLUMNS.keys
    keys -= CUSTOMER_KEYS unless query.context.capability?(:customers_view)
    keys -= SLA_KEYS unless query.context.capability?(:sla_view)
    keys -= HISTORY_KEYS unless query.context.capability?(:history_view)
    keys -= [:conversation_ids] unless query.context.capability?(:conversations_view)
    keys.index_with { |key| COLUMNS.fetch(key) }
  end

  def each_row
    return enum_for(:each_row) unless block_given?

    presenter = JrcServiceDesk::Presenter.new(user_context: query.context.to_h, read_only: true)
    query.relation.includes(:unit, :service, :category, :subcategory, :priority, :status, :queue, :team,
                            created_by_membership: { account_user: :user }, assignee_membership: { account_user: :user })
         .find_each(batch_size: 200) do |ticket|
      record = presenter.ticket(ticket)
      policy = JrcServiceDesk::TicketPolicy.new(query.context.to_h, ticket)
      data = basic(ticket, record)
      history(ticket, data) if policy.view_history?
      if policy.view_conversations?
        @conversation_ids ||= query.channels.pluck(:ticket_id, :conversation_id).group_by(&:first)
        data[:conversation_ids] = @conversation_ids.fetch(ticket.id, []).map(&:last).join('; ')
      end
      clocks(ticket, record, data) if policy.view_sla?
      surveys(ticket, data) if policy.view_customer?
      yield data
    end
  end

  def criteria
    rows = [['Relatório', 'Service Desk — chamados'], ['Versão', 2], ['Account', query.context.account.id],
            ['Empresa operadora', query.unit.operator_company.name], ['Unidade', query.unit.name],
            ['Gerado em', stamp(observed_at)], ['Fuso horário', timezone], ['Usuário', query.context.user.name],
            ['E-mail do exportador', query.context.user.email], ['AccountUser', query.context.account_user.id],
            ['Total autorizado', count], ['Período', 'Abertura >= de; abertura < até'],
            ['SLA', 'Último ciclo nativo; sem medição não é zero; SLA histórico não é recalculado'],
            ['Satisfação', 'Respostas autorizadas vinculadas aos chamados desta coorte de abertura'],
            ['Ausências', 'Em branco = não disponível ou não autorizado; sem estimativas']]
    query.filters.except('page', 'per_page').each { |key, value| rows << [key, value] }
    rows
  end

  def summary_rows
    rows = [['Indicador', 'Valor'], ['Total de chamados', count]]
    metrics.fetch(:phases).each { |phase, value| rows << [PHASE_LABELS.fetch(phase), value] }
    rows << ['Taxa de resolução (%)', metrics[:resolution_rate]]
    metrics[:sla]&.each do |kind, values|
      values.each { |key, value| rows << ["#{CLOCK_LABELS.fetch(kind.to_sym)} — #{SLA_LABELS.fetch(key)}", value] if SLA_LABELS.key?(key) }
    end
    metrics.dig(:by_status, :items).each do |row|
      status = JrcServiceDesk::TicketStatus.find_by(account_id: query.context.account.id, unit_id: query.unit.id, id: row[:id])
      rows << ["Status: #{status&.name}", row[:count]]
    end
    rows << ['Reaberturas', metrics.dig(:reopen, :events)]
    %i[csat nps ces response_count].each { |key| rows << ["Satisfação: #{key}", metrics.dig(:satisfaction, key)] }
    rows
  end

  def stamp(value)
    value&.in_time_zone(timezone)&.iso8601(6)
  end

  private

  def basic(ticket, record)
    { id: ticket.id.to_s, number: record[:number], title: record[:title], company: record.dig(:company, :name),
      requester: record.dig(:requester, :name), email: record.dig(:requester, :email), phone: record.dig(:requester, :phone_number),
      contact_id: record.dig(:requester, :id), unit: ticket.unit.name, service: record.dig(:service, :name), category: record.dig(:category, :name),
      subcategory: record.dig(:subcategory, :name), catalogue_item: record.dig(:ticket_type, :name),
      priority: record.dig(:priority, :name), status: record.dig(:status, :name), queue: record.dig(:queue, :name),
      team: record.dig(:team, :name), assignee: record.dig(:assignee, :name),
      description: ActionController::Base.helpers.strip_tags(record[:description].to_s).truncate(500),
      impact: record[:impact_code], urgency: record[:urgency_code], source: record[:source],
      opened_at: stamp(ticket.opened_at), updated_at: stamp(ticket.updated_at) }
  end

  def history(ticket, data)
    transitions = ticket.lifecycle_transitions.includes(actor_membership: { account_user: :user }).order(:occurred_at, :id).to_a
    resolved = transitions.reverse.find { |row| row.action == 'resolve' }
    closed = transitions.reverse.find { |row| row.action == 'close' }
    reopen = transitions.select { |row| row.action == 'reopen' }
    pauses = ticket.lifecycle_pauses.order(:id).to_a
    data.merge!(creator: ticket.created_by_membership.account_user.user.name, resolver: resolved&.actor_membership&.account_user&.user&.name,
                resolved_at: stamp(resolved&.occurred_at), closed_at: stamp(closed&.occurred_at),
                total_seconds: closed ? (closed.occurred_at - ticket.opened_at).to_i : nil,
                reason: closed&.payload&.dig('closing_reason'), pause_count: pauses.length, pause_reasons: pauses.map(&:reason_code).uniq.join('; '),
                paused_seconds: pauses.sum { |row| [(row.ended_at || observed_at) - row.started_at, 0].max }.round,
                reopen_count: reopen.length, last_reopened_at: stamp(reopen.last&.occurred_at))
    pauses.each { |row| extra['Pausas'] << [ticket.id.to_s, row.reason_code, stamp(row.started_at), stamp(row.ended_at)] } if collect_details
    reopen.each { |row| extra['Reaberturas'] << [ticket.id.to_s, stamp(row.occurred_at), row.to_status_id] } if collect_details
  end

  def clocks(ticket, record, data)
    clocks = Array(record.dig(:sla, :clocks))
    data[:sla_state] = clocks.empty? ? 'sem_medicao' : record.dig(:sla, :state)
    clocks.each do |clock|
      kind = clock.fetch(:kind)
      # Completed-clock compliance uses the same achieved_at/due_at definition as Metrics.
      result = if clock[:state] == 'completed'
                 Time.iso8601(clock[:achieved_at]) <= Time.iso8601(clock[:due_at]) ? 'dentro_do_prazo' : 'vencido'
               else
                 clock[:deadline_state]
               end
      data["#{kind}_budget".to_sym] = clock[:budget_seconds]
      data["#{kind}_result".to_sym] = result
      data["#{kind}_seconds".to_sym] = clock[:state] == 'completed' ? clock[:elapsed_seconds] : nil
      data["#{kind}_at".to_sym] = clock[:achieved_at] && stamp(Time.iso8601(clock[:achieved_at]))
      data[:sla_due_at] = stamp(Time.iso8601(clock[:due_at])) if kind == 'resolution'
      data[:business_seconds] = data[:resolution_seconds] if kind == 'resolution' && clock[:time_basis] == 'business'
      if collect_details
        extra['SLA'] << [ticket.id.to_s, kind, clock[:state], result, clock[:budget_seconds], clock[:elapsed_seconds],
                         stamp(Time.iso8601(clock[:due_at])), clock[:achieved_at], clock[:time_basis]]
      end
    end
    ticket.ola_clocks.includes(:queue, :sla_snapshot).order(:id).each do |clock|
      projection = JrcServiceDesk::ClockProjection.new(clock, now: observed_at).call
      if collect_details
        extra['OLA'] << [ticket.id.to_s, clock.queue.name, clock.kind, projection[:deadline_state], clock.budget_seconds,
                         projection[:elapsed_seconds], stamp(clock.started_at), stamp(clock.ended_at)]
      end
    end
  end

  def surveys(ticket, data)
    @surveys ||= JrcServiceDesk::ReportSurveyScope.for(query).where.not(responded_at: nil).order(:responded_at, :id).group_by(&:source_id)
    rows = @surveys.fetch(ticket.id, [])
    rows.each do |row|
      score = row.score
      if %w[csat ces].include?(row.kind) && row.definition_snapshot.dig('settings', 'service_desk_model')
        score = JrcRelationship::SurveyScale.normalize(score, row.questions.first, low: row.kind == 'csat' ? 1 : 0, high: row.kind == 'csat' ? 5 : 10)
      end
      score = 10 - score if row.kind == 'ces' && score && row.definition_snapshot.dig('settings', 'ces_direction') == 'lower_is_better'
      data[row.kind.to_sym] = score if %w[csat nps ces].include?(row.kind)
      extra['Satisfação'] << [ticket.id.to_s, row.kind, score, stamp(row.responded_at), row.comment] if collect_details
    end
    latest = rows.last
    data.merge!(survey_responded_at: stamp(latest.responded_at), survey_comment: latest.comment) if latest
  end
end
