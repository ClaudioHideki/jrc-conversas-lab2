class JrcNico::ConversationRadar
  PAGE_SIZE = 20
  WAIT_MINUTES = 10
  INACTIVE_HOURS = 24
  FIELDS = %w[id display_id inbox_id status assignee_id assignee_agent_bot_id waiting_since last_activity_at created_at].freeze

  def initialize(access:, arguments:)
    @access = access.authorize!
    @arguments = arguments
    @now = Time.current
  end

  def call
    scope = active_scope
    waiting = scope.where.not(waiting_since: nil).where('waiting_since <= ?', @now)
    relations = {
      'waiting' => waiting,
      'waiting_alert' => waiting.where('waiting_since <= ?', @now - WAIT_MINUTES.minutes),
      'unassigned' => scope.where(assignee_id: nil, assignee_agent_bot_id: nil),
      'inactive' => scope.where('COALESCE(conversations.last_activity_at, conversations.created_at) <= ?', @now - INACTIVE_HOURS.hours)
    }
    categories = relations.transform_values { |relation| project(relation) }
    { version: 1, generated_at: @now.iso8601, window: 'active_backlog', waiting_threshold_is_sla: false,
      criteria: criteria, categories: categories,
      conversation_ids: categories.values.flat_map { |group| group[:items].pluck(:conversation_id) }.uniq }
  end

  private

  def active_scope
    scope = Conversations::PermissionFilterService.new(@access.account.conversations, @access.user, @access.account).perform
    if @arguments['inbox_id']
      inbox = @access.account.inboxes.find_by(id: @arguments['inbox_id'])
      raise Pundit::NotAuthorizedError unless inbox && @access.inbox_visible?(inbox)

      scope = scope.where(inbox_id: inbox.id)
    end
    scope.where(status: %w[open pending]).where('conversations.created_at <= ?', @now)
  end

  def project(scope)
    page = @arguments.fetch('page', 1)
    total = scope.distinct.count(:id)
    records = scope.distinct.reorder(id: :asc).offset((page - 1) * PAGE_SIZE).limit(PAGE_SIZE).select(*FIELDS)
    items = records.map { |record| record.attributes.symbolize_keys.merge(conversation_id: record.display_id) }
    { total: total, page: page, page_size: PAGE_SIZE, has_more: total > page * PAGE_SIZE,
      next_page: total > page * PAGE_SIZE && page < 20 ? page + 1 : nil, page_limit: 20, items: items }
  end

  def criteria
    { status: %w[open pending], waiting: 'Native waiting_since present and not in the future',
      waiting_alert_minutes: WAIT_MINUTES, unassigned: 'No human assignee and no AgentBot',
      inactive_hours: INACTIVE_HOURS, inactive: 'Native last_activity_at, falling back to created_at; not evidence of abandonment',
      consistency: 'Current authorized database queries; not a frozen remote WhatsApp snapshot' }
  end
end
