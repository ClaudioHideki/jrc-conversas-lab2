# Read-only projections from native authorized conversation/ticket sources.
class JrcCustomers::AttendanceMetrics
  attr_reader :account

  def initialize(account:, user:, member:, customer:)
    @account = account
    @user = user
    @member = member
    @customer = customer
    @user_context = { account: account, user: user, account_user: member }
    @visibility = JrcCustomers::Visibility.new(account: account, user: user, account_user: member)
  end

  def call(filters = {})
    @period = period(filters)
    select_channel(filters[:channel].presence)
    { period: period_details, channel: @channel, channels: @channels,
      conversations: conversation_counts, messages: message_counts,
      csat: csat, conversation_sla: conversation_sla, ticket_sla: ticket_sla }
  end

  private

  def select_channel(channel)
    @conversations = @customer.conversations
    @channels = @conversations.joins(:inbox).distinct.pluck('inboxes.channel_type').sort
    raise ActionController::BadRequest, 'Invalid channel' if channel && @channels.exclude?(channel)

    @channel = channel
    @conversations = @conversations.joins(:inbox).where(inboxes: { channel_type: channel }) if channel
  end

  def conversation_counts
    records = @conversations.where(created_at: @period)
    { created: records.count, current_statuses: records.group(:status).count,
      by_channel: records.joins(:inbox).group('inboxes.channel_type').count }
  end

  def message_counts
    records = account.messages.where(conversation_id: @conversations.select(:id), private: false, created_at: @period).where(message_type: [0, 1])
    { incoming: records.where(message_type: 0).count, outgoing: records.where(message_type: 1).count }
  end

  def period(filters)
    zone = Time.find_zone(account.reporting_timezone) || Time.zone
    today = Time.current.in_time_zone(zone).to_date
    default = filters[:from].blank? && filters[:to].blank?
    first = default ? today - 29 : parse_date(filters[:from])
    last = default ? today : parse_date(filters[:to])
    raise ActionController::BadRequest, 'Invalid period (maximum 366 days)' if last < first || (last - first) > 365

    midnight(zone, first)...midnight(zone, last + 1)
  end

  def midnight(zone, date)
    zone.local(date.year, date.month, date.day)
  end

  def parse_date(value)
    raise ActionController::BadRequest, 'Provide both dates as YYYY-MM-DD' unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    Date.iso8601(value)
  rescue Date::Error
    raise ActionController::BadRequest, 'Invalid date'
  end

  def period_details
    { from: @period.begin.to_date.iso8601, to: (@period.end - 1.second).to_date.iso8601, timezone: @period.begin.time_zone.tzinfo.name }
  end

  def csat
    return { available: false, reason: 'permission' } unless CsatSurveyResponsePolicy.new(@user_context, CsatSurveyResponse).metrics?

    responses = native_csat.where(created_at: @period)
    ratings = responses.group(:rating).count
    total = ratings.values.sum
    satisfied = ratings.sum { |rating, count| rating.to_f >= 4 ? count : 0 }
    { available: true, responses: total, ratings: ratings,
      satisfied_percent: total.positive? ? (satisfied * 100.0 / total).round(2) : nil }
  end

  def native_csat
    # The native adapter of a restricted shared survey must not reappear here.
    native = account.csat_survey_responses.where(conversation_id: @conversations.select(:id))
                    .where.not(message_id: JrcRelationship::SurveyMetrics.managed_message_ids(self))
    return native unless account.feature_enabled?('jrc_relationship')

    context = JrcRelationship::Context.new(@member)
    surveys = context.records(JrcRelationship::Survey, survey_action: 'report')
                     .where(source_type: 'Conversation', source_id: @conversations.select(:id))
    surveys = JrcRelationship::SurveyModelAccess.visible_scope(context, surveys, action: 'report', share: 'share_reports')
    JrcRelationship::SurveyMetrics.csat(context: context, surveys: surveys, conversations: @conversations)
  rescue Pundit::NotAuthorizedError
    native
  end

  def conversation_sla
    # Matches AppliedSlasController's administrator check and native applicability scope.
    return { available: false, reason: 'permission' } unless @member.administrator?
    return { available: false, reason: 'not_enabled' } unless account.feature_enabled?('sla') && defined?(::AppliedSla)

    records = account.applied_slas.with_sla_applicable_conversation.where(conversation_id: @conversations.select(:id), created_at: @period)
    { available: true, applied: records.count, with_recorded_miss: records.missed.count, current_statuses: records.group(:sla_status).count }
  end

  def ticket_sla
    return { available: false, reason: 'permission' } unless @visibility.service_desk_sla?

    clocks = @visibility.sla_clocks(@customer.tickets).where(created_at: @period)
    { available: true, clocks: clocks.count, current_states: clocks.group(:state).count,
      currently_breached_running_clocks: JrcServiceDesk::ClockBreachQuery.count(clocks) }
  end
end
