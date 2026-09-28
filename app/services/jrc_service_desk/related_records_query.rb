# frozen_string_literal: true

class JrcServiceDesk::RelatedRecordsQuery
  KINDS = %w[notes events sla conversations status_options].freeze
  def initialize(user_context:, ticket:, kind:, parameters: {})
    @context = JrcServiceDesk::OperationalContext.new(user_context)
    @ticket = ticket
    @kind = kind.to_s
    raise ArgumentError, 'Unknown relation' unless KINDS.include?(@kind)
    Pundit.authorize(@context.to_h, ticket, { 'notes' => :view_notes?, 'events' => :view_history?, 'sla' => :view_sla?, 'conversations' => :view_conversations?, 'status_options' => :show? }.fetch(@kind))
    @parameters = JrcServiceDesk::QueryParameters.new(JrcServiceDesk::Input.attributes(parameters, %w[page per_page]))
  end

  def collection
    records = case @kind
              when 'notes' then scoped(JrcServiceDesk::TicketNote).includes(author_membership: { account_user: :user }).order(created_at: :desc, id: :desc)
              when 'events' then scoped(JrcServiceDesk::TicketEvent).includes(actor_membership: { account_user: :user }).order(created_at: :desc, id: :desc)
              when 'sla'
                latest = @ticket.sla_snapshots.order(version: :desc).first
                scoped(JrcServiceDesk::SlaMilestone).where(sla_snapshot_id: latest&.id).order(:id)
              when 'conversations'
                # Do not change the CP2 denied bulk-scope. Authorize every candidate
                # with both TicketConversationPolicy and native ConversationPolicy.
                @ticket.ticket_conversations.where(account_id: @context.account.id, unit_id: @ticket.unit_id)
                  .includes(:conversation).order(:id).select { |link| Pundit.policy!(@context.to_h, link).show? }
              when 'status_options'
                Pundit.authorize(@context.to_h, @ticket, :change_work_status?, policy_class: JrcServiceDesk::WorkStatusPolicy)
                version = JrcServiceDesk::LifecycleSelector.new(@ticket).applicable
                ids = version.definition['transitions'].select { |r| r['action'] == 'work_status' && r['from_status_ids'].include?(@ticket.status_id) }.map { |r| r['to_status_id'] }
                Pundit.policy_scope!(@context.to_h, JrcServiceDesk::TicketStatus).where(unit_id: @ticket.unit_id, phase: 'open', active: true, id: ids)
                  .order(position: :asc, id: :asc)
              end
    total = records.is_a?(Array) ? records.length : records.count
    items = records.is_a?(Array) ? (records.slice(@parameters.offset, @parameters.per_page) || []) : records.offset(@parameters.offset).limit(@parameters.per_page)
    { items: items, meta: { total: total, page: @parameters.page, per_page: @parameters.per_page } }
  end

  private

  def scoped(model)
    Pundit.authorize(@context.to_h, model, :index?)
    Pundit.policy_scope!(@context.to_h, model).where(ticket_id: @ticket.id)
  end
end
