# frozen_string_literal: true

class JrcServiceDesk::TicketQuery
  attr_reader :context, :parameters, :relation
  CATALOGS = { 'status_id' => JrcServiceDesk::TicketStatus, 'priority_id' => JrcServiceDesk::Priority,
               'category_id' => JrcServiceDesk::Category, 'queue_id' => JrcServiceDesk::Queue }.freeze
  SORTS = { 'updated_at_desc' => { updated_at: :desc, id: :desc },
            'created_at_desc' => { created_at: :desc, id: :desc },
            'created_at_asc' => { created_at: :asc, id: :asc } }.freeze

  def initialize(user_context:, parameters: {}, scope: nil)
    @context = JrcServiceDesk::OperationalContext.new(user_context)
    Pundit.authorize(context.to_h, JrcServiceDesk::Ticket, :index?)
    @parameters = JrcServiceDesk::QueryParameters.new(parameters)
    # Intersect even when a controller provides policy_scope; callers cannot broaden it.
    authorized = Pundit.policy_scope!(context.to_h, JrcServiceDesk::Ticket)
    @relation = scope ? authorized.where(id: scope.select(:id)) : authorized
    apply_filters!
  end

  def collection
    { items: relation.order(SORTS.fetch(parameters['sort'] || 'updated_at_desc')).offset(parameters.offset).limit(parameters.per_page),
      meta: { total: relation.count, page: parameters.page, per_page: parameters.per_page } }
  end

  private

  def apply_filters!
    units = context.view_unit_scope
    if parameters['operator_company_id']
      id = parameters['operator_company_id']
      raise ActiveRecord::RecordNotFound unless units.exists?(operator_company_id: id)
      units = units.where(operator_company_id: id)
    end
    if parameters['unit_id']
      units.find(parameters['unit_id'])
      units = units.where(id: parameters['unit_id'])
    end
    @relation = relation.where(unit_id: units.select(:id))
    CATALOGS.each do |key, model|
      next unless parameters[key]
      model.where(account_id: context.account.id, unit_id: units.select(:id)).find(parameters[key])
      @relation = relation.where(key => parameters[key])
    end
    if parameters['assignee_id']
      grants = JrcServiceDesk::UnitMembership.where(account_id: context.account.id, unit_id: units.select(:id),
                                                      account_user_id: parameters['assignee_id'])
      raise ActiveRecord::RecordNotFound unless grants.exists?
      @relation = relation.where(assignee_membership_id: grants.select(:id))
    end
    if parameters['mine']
      @relation = relation.where(assignee_membership_id: context.active_memberships.select(:id))
    end
    @relation = relation.where(origin_channel: parameters['source']) if parameters['source']
    return if parameters['q'].nil? || parameters['q'].empty?

    q = parameters['q']
    like = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
    match = relation.where('jrc_service_desk_tickets.title ILIKE :q OR jrc_service_desk_tickets.description ILIKE :q', q: like)
    match = match.or(relation.where(id: JrcServiceDesk::Input.id(q))) if q.match?(/\A[1-9]\d{0,18}\z/) && q.to_i <= 9_223_372_036_854_775_807
    @relation = match
  end
end
