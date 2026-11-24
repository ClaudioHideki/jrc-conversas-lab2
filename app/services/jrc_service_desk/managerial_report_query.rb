# frozen_string_literal: true

class JrcServiceDesk::ManagerialReportQuery
  FIRST_DATE = Date.new(2026, 1, 1)
  NATIVE_ORIGINS = %w[manual portal].freeze
  IMPORTED_ORIGIN = 'legacy_import'
  ORIGINS = (NATIVE_ORIGINS + [IMPORTED_ORIGIN]).freeze
  DATES = %w[opened_at created_at updated_at].freeze
  GROUPS = %w[day week month year].freeze
  DIMENSIONS = {
    'status_id' => :status, 'priority_id' => :priority, 'service_id' => :service, 'category_id' => :category,
    'subcategory_id' => :subcategory, 'ticket_type_id' => :ticket_type, 'queue_id' => :queue, 'team_id' => :team,
    'assignee_membership_id' => :assignee_membership, 'requester_id' => :requester, 'company_id' => :master_company,
    'establishment_company_id' => :establishment_company
  }.freeze
  CUSTOMER_FIELDS = %w[requester_id company_id establishment_company_id].freeze
  FIELDS = (DIMENSIONS.keys + %w[unit_id origin phase date_field group_by from to page per_page]).freeze
  ASSOCIATIONS = (DIMENSIONS.except(*CUSTOMER_FIELDS, 'assignee_membership_id').values + [{ assignee_membership: { account_user: :user } }]).freeze
  attr_reader :context, :unit, :timezone, :filters, :relation, :date_field, :group_by

  def initialize(context, unit_id, parameters: {}, action: :view)
    @context = context
    @unit = context.unit_scope.find(JrcServiceDesk::Input.id(unit_id))
    raise Pundit::NotAuthorizedError unless context.managerial_reporting_allowed?(action, unit: unit)

    @timezone = Time.find_zone(context.account.reporting_timezone) || Time.zone
    @base = ticket_scope('reports_view').where(unit_id: unit.id, opened_at: midnight(FIRST_DATE)..)
    @base = @base.where(id: ticket_scope('reports_export').select(:id)) if action == :export
    @filters = JrcServiceDesk::Input.attributes(parameters, FIELDS)
    @date_field = filters.fetch('date_field', 'opened_at')
    @group_by = filters.fetch('group_by', 'month')
    raise ArgumentError unless DATES.include?(date_field) && GROUPS.include?(group_by)

    @relation = filter_dates(@base, date_field, filters)
    @relation = filter_origin(relation, filters.fetch('origin', 'all'))
    @relation = filter_phase(relation, filters['phase']) if filters.key?('phase')
    @relation = filter_dimensions(relation, filters)
  end

  def collection
    page = JrcServiceDesk::Input.version(filters.fetch('page', 1))
    per_page = JrcServiceDesk::Input.version(filters.fetch('per_page', 25))
    raise ArgumentError unless page.between?(1, 1_000_000) && per_page.between?(1, 100)

    items = relation.order(date_field => :desc, id: :desc).limit(per_page).offset((page - 1) * per_page)
                    .preload(*ASSOCIATIONS).to_a
    { items: serialize(items), meta: { total: relation.count, page: page, per_page: per_page } }
  end

  def relation_for(permission)
    relation.where(id: ticket_scope(permission).select(:id))
  end

  def each_row_batch
    relation.preload(*ASSOCIATIONS).find_in_batches(batch_size: 200) { |tickets| yield serialize(tickets) }
  end

  def dimension_counts(field)
    records, label = dimension_records(field)
    scoped = relation
    if CUSTOMER_FIELDS.include?(field)
      scoped = relation_for('customers_view')
      scoped = scoped.where(field => records.select(:id)).or(scoped.where(field => nil))
    end
    counts = scoped.group(field).order(Arel.sql('COUNT(*) DESC'), field).limit(21).count
    names = records.where(id: counts.keys.compact).pluck(records.klass.arel_table[:id], label).to_h
    rows = counts.first(20).map { |id, count| { id: id&.to_s, name: names[id], count: count } }
    if rows.none? { |row| row[:id].nil? }
      missing = scoped.where(field => nil).count
      rows << { id: nil, name: nil, count: missing } if missing.positive?
    end
    { items: rows, truncated: counts.size > 20 }
  end

  def customer_signature
    CUSTOMER_FIELDS.index_with do |field|
      records, = dimension_records(field)
      records.where(id: relation.select(field)).reorder(records.klass.arel_table[:id]).ids
    end
  end

  def selected_dimensions
    filters.slice(*DIMENSIONS.keys).to_h do |field, value|
      name = nil
      unless value == 'unassigned'
        records, label = dimension_records(field)
        name = records.where(id: value).pick(label)
      end
      [field, name]
    end
  end

  def options(field, search)
    records, label = dimension_records(field)
    if search.present?
      term = "%#{ActiveRecord::Base.sanitize_sql_like(search)}%"
      records = records.where(label.matches(term))
    end
    ids = records.klass.arel_table[:id]
    rows = records.order(label.asc, ids.asc).limit(51).pluck(ids, label)
    { items: rows.first(50).map { |id, name| { id: id.to_s, name: name.to_s.presence || id.to_s } }, has_more: rows.size > 50 }
  end

  private

  def ticket_scope(permission)
    JrcServiceDesk::TicketPolicy::Scope.new(@context.to_h, JrcServiceDesk::Ticket).resolve_for(permission)
  end

  def midnight(day)
    timezone.local(day.year, day.month, day.day)
  end

  def date(value)
    raise ArgumentError unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    day = Date.iso8601(value)
    raise ArgumentError if day < FIRST_DATE

    day
  end

  def filter_dates(relation, field, filters)
    from = date(filters['from']) if filters.key?('from')
    to = date(filters['to']) if filters.key?('to')
    raise ArgumentError if from && to && from > to

    column = JrcServiceDesk::Ticket.arel_table[field]
    relation = relation.where(column.gteq(midnight(from))) if from
    relation = relation.where(column.lt(midnight(to.next_day))) if to
    relation
  end

  def filter_origin(relation, origin)
    case origin
    when 'all' then relation
    when 'native' then relation.where(origin_channel: NATIVE_ORIGINS)
    when *ORIGINS then relation.where(origin_channel: origin)
    when 'unknown' then relation.where.not(origin_channel: ORIGINS)
    else raise ArgumentError
    end
  end

  def filter_phase(relation, phase)
    raise ArgumentError unless JrcServiceDesk::TicketStatus::PHASES.include?(phase)

    relation.joins(:status).where(jrc_service_desk_ticket_statuses: { phase: phase })
  end

  def filter_dimensions(relation, filters)
    filters.slice(*DIMENSIONS.keys).each do |field, value|
      if value == 'unassigned' && field == 'assignee_membership_id'
        relation = relation.where(assignee_membership_id: nil)
        next
      end

      id = JrcServiceDesk::Input.id(value)
      records, = dimension_records(field)
      raise ActiveRecord::RecordNotFound unless records.exists?(id: id)

      relation = relation.where(field => id)
      relation = relation.where(id: customer_tickets.select(:id)) if CUSTOMER_FIELDS.include?(field)
    end
    relation
  end

  def customer_tickets
    @customer_tickets ||= if @context.capability?(:customers_view)
                           @base.where(id: ticket_scope('customers_view').select(:id))
                         else
                           @base.none
                         end
  end

  def dimension_records(field)
    klass = JrcServiceDesk::Ticket.reflect_on_association(DIMENSIONS.fetch(field)).klass
    scoped_tickets = CUSTOMER_FIELDS.include?(field) ? customer_tickets : @base
    records = klass.where(account_id: @context.account.id, id: scoped_tickets.select(field))
    if field == 'assignee_membership_id'
      records = records.joins(account_user: :user).where(unit_id: unit.id)
      return [records, User.arel_table[:name]]
    end

    if klass == JrcCustomers::Company
      return [records.none, klass.arel_table[:name]] unless JrcCustomers::DirectoryPolicy.new(@context.to_h, :directory).access?

      records = JrcCrm::CorporateCoverage.new(account: @context.account, user: @context.user).companies(records)
    elsif klass == Contact && !Pundit.policy!(@context.to_h, Contact).index?
      records = records.none
    elsif klass < JrcServiceDesk::UnitRecord
      records = records.where(unit_id: unit.id)
    end
    [records, klass.arel_table[:name]]
  end

  def serialize(items)
    return [] if items.empty?

    customer_ids = customer_tickets.where(id: items.map(&:id)).pluck(:id).to_set
    customer_names = CUSTOMER_FIELDS.index_with do |field|
      records, label = dimension_records(field)
      records.where(id: items.filter_map { |ticket| ticket[field] }).pluck(records.klass.arel_table[:id], label).to_h
    end
    items.map do |ticket|
      names = DIMENSIONS.except(*CUSTOMER_FIELDS, 'assignee_membership_id').transform_values { |association| ticket.public_send(association)&.name }
      customer_names.each { |field, labels| names[field] = labels[ticket[field]] } if customer_ids.include?(ticket.id)
      { id: ticket.id.to_s, title: ticket.title, phase: ticket.status.phase, initial: ticket.status.initial?,
        status: names['status_id'], priority: names['priority_id'],
        requester: names['requester_id'], company: names['company_id'], establishment: names['establishment_company_id'],
        unit: unit.name, assignee: ticket.assignee_account_user&.user&.name, team: names['team_id'], queue: names['queue_id'],
        service: names['service_id'], category: names['category_id'], subcategory: names['subcategory_id'], ticket_type: names['ticket_type_id'],
        origin: ticket.origin_channel.in?(ORIGINS) ? ticket.origin_channel : 'unknown', origin_code: ticket.origin_channel,
        opened_at: stamp(ticket.opened_at), created_at: stamp(ticket.created_at), updated_at: stamp(ticket.updated_at) }
    end
  end

  def stamp(time)
    time.in_time_zone(timezone).iso8601
  end
end
