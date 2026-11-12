# Applies list filters BEFORE pagination to an already authorized Activity scope.
# This class never selects a tenant, owner authority, or changes an activity.
class JrcCrm::CalendarFilters
  TYPES = %w[call meeting whatsapp email follow_up task demonstration].freeze
  STATES = %w[open overdue completed].freeze

  def initialize(scope:, params:, now: Time.current)
    @scope = scope
    @params = params
    @now = now
  end

  def call
    rows = @scope
    type = choice!(:activity_type, TYPES)
    status = choice!(:status, STATES)
    rows = rows.where(activity_type: type) if type
    case status
    when 'completed'
      rows = rows.where("jrc_crm_activities.completed_at IS NOT NULL OR jrc_crm_activities.status = ?", 'completed')
    when 'open', 'overdue'
      rows = rows.where(completed_at: nil).where.not(status: %w[completed cancelled])
      rows = rows.where('jrc_crm_activities.due_at < ?', @now) if status == 'overdue'
    end
    search = search!
    return rows unless search

    # Fields match the source labels already returned by ActivitySerializer.
    # Bind parameters and LIKE escaping ensure user input is not SQL syntax.
    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(search)}%"
    columns = %w[jrc_crm_activities.title jrc_crm_activities.description jrc_crm_deals.title jrc_crm_leads.name contacts.name companies.name]
    rows.left_joins(:deal, :lead, :contact, :company)
        .where(columns.map { |column| "#{column} ILIKE :query" }.join(' OR '), query: pattern)
  end

  private

  def choice!(name, choices)
    value = @params[name]
    return if value.nil? || value == ''
    return value if value.is_a?(String) && choices.include?(value)

    raise JrcCrm::CalendarPage::InvalidQuery, "Invalid calendar #{name}"
  end

  def search!
    value = @params[:search]
    return if value.nil? || value == ''
    unless value.is_a?(String) && value.length <= 256 && !value.include?("\0")
      raise JrcCrm::CalendarPage::InvalidQuery, 'Invalid calendar search'
    end

    value = value.strip
    value unless value.empty?
  end
end
