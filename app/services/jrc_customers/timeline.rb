# No new event table. Each source contributes at most page_size+1 rows.
class JrcCustomers::Timeline
  class InvalidCursor < StandardError; end
  def initialize(context:, account:, user:)
    @context, @account, @user = context, account, user
  end

  def call(cursor: nil, limit: 30)
    limit = limit.to_i.clamp(1, 50)
    position = decode(cursor) if cursor.present?
    events = @context.timeline_sources.flat_map do |source, (relation, clock)|
      relation = before_cursor(relation, clock, source, position) if position
      relation.reorder(clock => :desc, id: :desc).limit(limit + 1).map do |record|
        timeline_event(source, record, clock)
      end
    end
    events.sort_by! { |row| [row[:at], row[:source], row[:id]] }
    events.reverse!
    page = events.first(limit)
    next_cursor = encode(page.last) if events.length > limit
    { payload: page.map { |row| row.merge(at: row[:at].iso8601(6)) }, next_cursor: next_cursor }
  end

  private

  def verifier
    Rails.application.message_verifier('jrc_customer_master_timeline')
  end

  def context_key
    [@account.id, @user.id, @context.resource_key].join(':')
  end

  def encode(event)
    verifier.generate({ context: context_key, at: event[:at].iso8601(6), source: event[:source], id: event[:id] }, expires_in: 1.hour)
  end

  def decode(cursor)
    raise InvalidCursor, 'Invalid cursor' unless cursor.is_a?(String) && cursor.bytesize <= 4096
    payload = verifier.verified(cursor)
    value = payload.is_a?(Hash) ? payload.with_indifferent_access : nil
    raise InvalidCursor, 'Expired or invalid cursor' unless value && value[:context] == context_key

    value.merge(at: Time.iso8601(value[:at]), id: Integer(value[:id]))
  rescue ArgumentError, TypeError
    raise InvalidCursor, 'Invalid cursor'
  end

  def before_cursor(relation, clock, source, position)
    table = relation.klass.arel_table
    predicate = table[clock].lt(position[:at])
    if source < position[:source]
      predicate = predicate.or(table[clock].eq(position[:at]))
    elsif source == position[:source]
      predicate = predicate.or(table[clock].eq(position[:at]).and(table[:id].lt(position[:id])))
    end
    relation.where(predicate)
  end

  def timeline_event(source, record, clock)
    return event(source, record, clock) unless source.start_with?('relationship_')

    { source: source, id: record.id, at: record.public_send(clock) }
      .merge(JrcRelationship::CustomerTimeline.event(source, record))
  end

  def event(source, record, clock)
    values = { source: source, id: record.id, at: record.public_send(clock) }
    case source
    when 'message'
      values.merge(title: record.message_type == 'incoming' ? 'Mensagem recebida' : 'Mensagem enviada',
                   conversation_id: record.conversation_id, contact_id: record.sender_type == 'Contact' ? record.sender_id : nil)
    when 'audit'
      # Do not expose snapshot JSON, identifiers or hidden resource data through an aggregate.
      values.merge(title: record.event_type, resource_type: record.resource_type, resource_id: record.resource_id)
    when 'ticket_event'
      action = record.data.is_a?(Hash) ? record.data['action'] : nil
      title = case action
              when 'resolve' then 'Chamado resolvido'
              when 'close' then 'Chamado encerrado'
              else record.event_type == 'ticket_created' ? 'Chamado criado' : 'Chamado atualizado'
              end
      values.merge(title: title, ticket_id: record.ticket_id)
    when 'project_event'
      title = record.action == 'projects.task.completed' ? 'Tarefa concluida' : 'Projeto / tarefa atualizado'
      if record.auditable_type == 'JrcProjects::Task' && record.after_data.is_a?(Hash) && record.after_data['status'] == 'completed'
        title = 'Tarefa concluida'
      end
      values.merge(title: title, resource_type: record.auditable_type, resource_id: record.auditable_id)
    when 'call'
      values.merge(title: 'Chamada registrada', direction: record.direction, duration_seconds: record.duration_seconds,
                   status: record.status, conversation_id: record.conversation_id)
    when 'campaign_sent'
      values.merge(title: 'Envio de campanha', campaign_id: record.campaign_id, status: record.status)
    else
      values.merge(title: record.title, activity_type: record.activity_type, status: record.status, deal_id: record.deal_id, lead_id: record.lead_id)
    end
  end
end
