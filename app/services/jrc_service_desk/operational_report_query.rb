# frozen_string_literal: true

require 'time'

# Reports use an explicit unit and intersect the native Ticket/Conversation scopes.
class JrcServiceDesk::OperationalReportQuery
  FIELDS = %w[unit_id service_id company_id inbox_id channel_type category_id priority_id from to page per_page].freeze
  attr_reader :context, :unit, :relation, :filters, :from, :to

  def initialize(user_context:, parameters:)
    @context = JrcServiceDesk::OperationalContext.new(user_context)
    unless context.capability?(:dashboard_view) && context.capability?(:tickets_view_all)
      raise Pundit::NotAuthorizedError, 'Operational reports require supervisor capabilities'
    end

    @filters = JrcServiceDesk::Input.attributes(parameters, FIELDS)
    @unit = context.unit_scope.find(JrcServiceDesk::Input.id(filters.fetch('unit_id')))
    @relation = JrcServiceDesk::TicketPolicy::Scope.new(context.to_h, JrcServiceDesk::Ticket).resolve.where(unit_id: unit.id)
    @from = timestamp(filters['from'])
    @to = timestamp(filters['to'])
    raise ArgumentError, 'Invalid time range' if from && to && from >= to

    apply_filters!
  end

  def collection
    page = JrcServiceDesk::Input.version(filters.fetch('page', 1))
    per_page = JrcServiceDesk::Input.version(filters.fetch('per_page', 25))
    raise ArgumentError, 'Invalid pagination' unless page.between?(1, 1_000_000) && per_page.between?(1, 100)

    { items: relation.order(opened_at: :desc, id: :desc).offset((page - 1) * per_page).limit(per_page),
      meta: { page: page, per_page: per_page, total: relation.count } }
  end

  def channels
    return nil unless context.capability?(:conversations_view)

    conversations = JrcServiceDesk::NativeExecutionContext.with(context.to_h) do
      JrcCustomers::Visibility.new(**context.to_h).conversations.where(account_id: context.account.id)
    end
    JrcServiceDesk::TicketConversation.where(account_id: context.account.id, unit_id: unit.id,
                                             ticket_id: relation.select(:id), conversation_id: conversations.select(:id))
                                      .joins(conversation: :inbox)
  end

  def customer_dimension?
    context.capability?(:customers_view) && JrcCustomers::DirectoryPolicy.new(context.to_h, :directory).access?
  end

  def during(scope, field)
    scope = scope.where("#{field} >= ?", from) if from
    scope = scope.where("#{field} < ?", to) if to
    scope
  end

  private

  def apply_filters!
    @relation = during(relation, 'jrc_service_desk_tickets.opened_at')
    { 'service_id' => JrcServiceDesk::Service, 'category_id' => JrcServiceDesk::Category,
      'priority_id' => JrcServiceDesk::Priority }.each do |field, model|
      next unless filters[field]

      id = JrcServiceDesk::Input.id(filters[field])
      model.where(account_id: context.account.id, unit_id: unit.id).find(id)
      @relation = relation.where(field => id)
    end
    if filters['company_id']
      raise Pundit::NotAuthorizedError unless customer_dimension?

      id = JrcServiceDesk::Input.id(filters['company_id'])
      JrcCustomers::Company.where(account_id: context.account.id).find(id)
      @relation = relation.where(company_id: id)
    end
    apply_channel!
  end

  def apply_channel!
    return unless filters['inbox_id'] || filters['channel_type']
    raise Pundit::NotAuthorizedError unless context.capability?(:conversations_view)

    linked = channels
    if filters['inbox_id']
      inbox = Inbox.where(account_id: context.account.id).find(JrcServiceDesk::Input.id(filters['inbox_id']))
      JrcServiceDesk::NativeExecutionContext.with(context.to_h) { Pundit.authorize(context.to_h, inbox, :show?) }
      linked = linked.where(inboxes: { id: inbox.id })
    end
    if filters['channel_type']
      JrcServiceDesk::OperationalRuleContract.predicates!('channel_type' => filters['channel_type'])
      linked = linked.where(inboxes: { channel_type: filters['channel_type'] })
    end
    @relation = relation.where(id: linked.reselect(:ticket_id))
  end

  def timestamp(value)
    return nil if value.nil?
    raise ArgumentError, 'Timestamp needs explicit timezone' unless value.is_a?(String) && value.match?(/(?:Z|[+-]\d{2}:\d{2})\z/)

    Time.iso8601(value)
  end
end
