class JrcServiceDesk::TicketTimeline
  PURPOSE = 'service_desk_timeline'.freeze

  def initialize(ticket:, context:)
    @ticket = ticket
    @context = context
  end

  def call(cursor: nil, per_page: 30, view: 'all', event_type: nil, author_id: nil, date_from: nil, date_to: nil)
    raise ArgumentError unless %w[all conversations notes history files].include?(view)

    @view = view
    @filters = { 'event_type' => event_type, 'author_id' => author_id, 'date_from' => date_from, 'date_to' => date_to }.compact
    raise ArgumentError unless @filters.empty? || view == 'history'

    @sources = JrcServiceDesk::TimelineSources.new(ticket: @ticket, context: @context).call(view: view)
    filter_history! unless @filters.empty?
    size = page_size(per_page)
    boundary = cursor && decode(cursor)
    rows = ActiveRecord::Base.connection.select_all(sql(boundary, size + 1)).to_a
    page = rows.first(size)
    { items: page.map { |row| project(row) }, next_cursor: rows.size > size ? encode(page.last) : nil, per_page: size }
  end

  private

  def page_size(value)
    size = value.is_a?(String) ? Integer(value, 10) : value
    raise ArgumentError unless size.is_a?(Integer) && size.between?(1, 100)

    size
  end

  def filter_history!
    events = @sources.fetch('event')
    if @filters['event_type']
      raise ArgumentError unless JrcServiceDesk::TicketEvent::TYPES.include?(@filters['event_type'])

      events = events.where(event_type: @filters['event_type'])
    end
    if @filters['author_id']
      @filters['author_id'] = JrcServiceDesk::Input.id(@filters['author_id'])
      actor = @context.account.account_users.find(@filters['author_id'])
      memberships = JrcServiceDesk::UnitMembership.where(account_id: @ticket.account_id, unit_id: @ticket.unit_id, account_user_id: actor.id)
      events = events.where(actor_membership_id: memberships.select(:id))
    end
    %w[date_from date_to].each do |key|
      next unless @filters[key]

      value = @filters[key]
      raise ArgumentError unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      date = Date.iso8601(value)
      date = date.next_day if key == 'date_to'
      events = events.where("created_at #{key == 'date_from' ? '>=' : '<'} ?", Time.zone.local(date.year, date.month, date.day))
    end
    raise ArgumentError if @filters['date_from'] && @filters['date_to'] && @filters['date_from'] > @filters['date_to']

    @sources['event'] = events
  end

  def sql(boundary, limit)
    queries = @sources.map do |kind, relation|
      table = relation.klass.table_name
      relation.reorder(nil).select("#{table}.id AS record_id, #{table}.created_at AS occurred_at, '#{kind}' AS origin").to_sql
    end
    "SELECT * FROM (#{queries.join(' UNION ALL ')}) timeline #{predicate(boundary)} " \
      "ORDER BY occurred_at DESC, origin ASC, record_id DESC LIMIT #{limit}"
  end

  def predicate(boundary)
    return '' unless boundary

    ActiveRecord::Base.sanitize_sql_array([
                                            'WHERE occurred_at < :at OR (occurred_at = :at AND ' \
                                            '(origin > :kind OR (origin = :kind AND record_id < :id)))',
                                            { at: boundary.fetch('occurred_at'), kind: boundary.fetch('origin'), id: boundary.fetch('record_id') }
                                          ])
  end

  def project(row)
    kind = row.fetch('origin')
    record = @sources.fetch(kind).find(row.fetch('record_id'))
    JrcServiceDesk::TimelinePresenter.new(context: @context, ticket: @ticket).call(kind, record)
  end

  def binding
    { 'account_id' => @ticket.account_id, 'unit_id' => @ticket.unit_id, 'ticket_id' => @ticket.id,
      'account_user_id' => @context.account_user.id, 'view' => @view, 'filters' => @filters }
  end

  def encode(row)
    Rails.application.message_verifier(PURPOSE).generate(binding.merge(row.slice('origin', 'record_id', 'occurred_at')), expires_in: 30.minutes,
                                                                                                                         purpose: PURPOSE)
  end

  def decode(cursor)
    value = Rails.application.message_verifier(PURPOSE).verified(cursor, purpose: PURPOSE)
    raise ArgumentError unless value.is_a?(Hash) && binding.all? { |key, expected| value[key] == expected } && @sources.key?(value['origin'])

    value
  end
end
