class JrcCustomers::OperationalContacts
  STATES = %w[in_service waiting active].freeze
  KINDS = %w[conversation activity follow_up ticket call].freeze

  def initialize(account:, actor:)
    @account = account
    @actor = actor
  end

  def call(params: {})
    filters = params.to_h.with_indifferent_access
    validate_filters!(filters)
    contacts, signals = authorized_sources
    days = filters.fetch(:days, 30).to_i.clamp(1, 365)
    relation = contacts.joins("INNER JOIN (#{summary(signals, days)}) movement ON movement.contact_id = contacts.id")
    relation = filter(relation, signals, filters)
    paginate(relation, filters, signals, days)
  end

  private

  def authorized_sources
    contacts = JrcCustomers::ContactDirectory.new(account: @account, actor: @actor).scope
    membership = @account.account_users.find_by!(user_id: @actor.id)
    signals = JrcCustomers::OperationalSources.new(account: @account, actor: @actor, membership: membership, contact_scope: contacts).sql
    [contacts, signals]
  end

  def paginate(relation, filters, signals, days)
    page = filters.fetch(:page, 1).to_i.clamp(1, 10_000)
    size = filters.fetch(:per_page, 25).to_i.clamp(1, 50)
    total = relation.count
    records = relation.select('contacts.*, movement.operational_status, movement.last_interaction_at')
                      .order(Arel.sql('movement.last_interaction_at DESC NULLS LAST, contacts.id DESC'))
                      .limit(size).offset((page - 1) * size).to_a
    { payload: serialize(records, signals), meta: { page: page, per_page: size, total: total, days: days } }
  end

  def validate_filters!(filters)
    raise ActionController::BadRequest, 'Invalid operational status' if filters[:status].present? && STATES.exclude?(filters[:status])
    raise ActionController::BadRequest, 'Invalid operational source' if filters[:kind].present? && KINDS.exclude?(filters[:kind])
  end

  def summary(signals, days)
    cutoff = ActiveRecord::Base.connection.quote(days.days.ago)
    <<~SQL.squish
      SELECT contact_id, MAX(occurred_at) AS last_interaction_at,
        CASE WHEN BOOL_OR(living AND state = 'open') THEN 'in_service'
          WHEN BOOL_OR(living AND state = 'waiting') THEN 'waiting' ELSE 'active' END AS operational_status
      FROM (#{signals}) signals GROUP BY contact_id
      HAVING BOOL_OR(living OR pending) OR MAX(occurred_at) >= #{cutoff}
    SQL
  end

  def filter(relation, signals, filters)
    relation = search(relation, filters[:q])
    relation = relation.where(movement: { operational_status: filters[:status] }) if filters[:status].present?
    if filters[:kind].present?
      quoted = ActiveRecord::Base.connection.quote(filters[:kind])
      relation = relation.where("contacts.id IN (SELECT contact_id FROM (#{signals}) sources WHERE kind = #{quoted})")
    end
    return relation if filters[:taxonomy_id].blank?

    taxonomy = JrcCustomers::Taxonomy.active.where(account_id: @account.id).find(filters[:taxonomy_id])
    ids = JrcCustomers::SegmentMembers.new(account: @account, actor: @actor, taxonomy: taxonomy).contacts.reselect(:id)
    relation.where(id: ids)
  end

  def search(relation, value)
    term = value.to_s.strip.first(200)
    return relation if term.blank?

    contacts = JrcCustomers::ContactQuery.new(account: @account, scope: relation, query: term, include_company: false).call
    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
    # DirectoryQuery also finds companies through their people. Here that would
    # expand a match on one person to every operational contact at that company.
    companies = @account.master_companies.where(
      'name ILIKE :q OR trade_name ILIKE :q OR customer_code ILIKE :q OR tax_id ILIKE :q OR ' \
      'email ILIKE :q OR phone_number ILIKE :q OR domain ILIKE :q',
      q: pattern
    )
    contacts.or(relation.where(company_id: companies.select(:id)))
  end

  def serialize(records, signals)
    rows = details(records.map(&:id), signals).group_by { |row| row['contact_id'] }
    user_ids = rows.values.flatten.pluck('actor_id').compact.uniq
    users = @account.users.where(id: user_ids).pluck(:id, :name).to_h
    JrcCustomers::Serializer.new(account: @account).contacts(records).zip(records).map do |contact, record|
      serialize_contact(contact, record, rows.fetch(record.id, []), users)
    end
  end

  def serialize_contact(contact, record, sources, users)
    context = sources.min_by { |row| [row['priority'], -row['record_id']] }
    action = sources.select { |row| row['pending'] }.min_by { |row| [row['due_at'] || Time.utc(9999), row['record_id']] }
    contact.merge('operational_status' => record['operational_status'], 'last_interaction_at' => record['last_interaction_at'],
                  'context' => present(context, users), 'next_action' => present(action, users))
  end

  def details(ids, signals)
    return [] if ids.empty?

    sql = <<~SQL.squish
      SELECT DISTINCT ON (contact_id, kind) * FROM (#{signals}) sources WHERE contact_id IN (#{ids.join(',')})
      ORDER BY contact_id, kind, priority ASC, pending DESC, due_at ASC NULLS LAST, occurred_at DESC NULLS LAST, record_id DESC
    SQL
    ActiveRecord::Base.connection.select_all(sql).to_a
  end

  def present(row, users)
    return nil unless row

    row.slice('kind', 'record_id', 'display_id', 'state', 'due_at', 'channel_type', 'channel_name', 'title')
       .merge('responsible' => users.key?(row['actor_id']) ? { id: row['actor_id'], name: users[row['actor_id']] } : nil)
  end
end
