class JrcServiceDesk::TicketTimeline
  PURPOSE = 'service_desk_timeline'.freeze

  def initialize(ticket:, context:)
    @ticket = ticket
    @context = context
    @sources = JrcServiceDesk::TimelineSources.new(ticket: ticket, context: context).call
  end

  def call(cursor: nil, per_page: 30)
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
    { 'account_id' => @ticket.account_id, 'unit_id' => @ticket.unit_id, 'ticket_id' => @ticket.id, 'account_user_id' => @context.account_user.id }
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
