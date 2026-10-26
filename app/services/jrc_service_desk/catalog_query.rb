# frozen_string_literal: true

class JrcServiceDesk::CatalogQuery
  MODELS = { 'queues' => JrcServiceDesk::Queue, 'priorities' => JrcServiceDesk::Priority,
             'categories' => JrcServiceDesk::Category, 'ticket_types' => JrcServiceDesk::TicketType, 'statuses' => JrcServiceDesk::TicketStatus,
             'units' => JrcServiceDesk::Unit, 'operator_companies' => JrcServiceDesk::OperatorCompany }.freeze
  NATIVE = %w[assignees requesters teams contracts].freeze
  attr_reader :context, :parameters, :unit_id, :resource

  def initialize(user_context:, resource:, parameters: {})
    @context = JrcServiceDesk::OperationalContext.new(user_context)
    Pundit.authorize(context.to_h, :lookup, :index?, policy_class: JrcServiceDesk::LookupPolicy)
    @resource = resource.to_s
    raise Pundit::NotAuthorizedError if @resource == 'requesters' && !context.capability?(:customers_view)
    raise ArgumentError, 'Unknown lookup' unless MODELS.key?(@resource) || NATIVE.include?(@resource)
    @parameters = JrcServiceDesk::QueryParameters.new(parameters, catalog: true)
    @unit_id = @parameters['unit_id']
    raise ArgumentError, 'Team filter requires assignees' if @parameters['team_id'] && @resource != 'assignees'
    raise ArgumentError, 'Queue filter requires assignees' if @parameters['queue_id'] && @resource != 'assignees'
    raise ArgumentError, 'Company filter requires requesters' if @parameters['company_id'] && @resource != 'requesters'
    @units = context.view_unit_scope
    if @parameters['operator_company_id']
      raise ActiveRecord::RecordNotFound unless @units.exists?(operator_company_id: @parameters['operator_company_id'])
      @units = @units.where(operator_company_id: @parameters['operator_company_id'])
    end
    if unit_id
      @units.find(unit_id)
      @units = @units.where(id: unit_id)
    end
    raise ArgumentError, 'Unit required for native lookup' if NATIVE.include?(@resource) && unit_id.nil?
    if @resource == 'assignees' && @parameters['queue_id']
      @assignee_queue = JrcServiceDesk::Queue.where(account_id: context.account.id, unit_id: unit_id, active: true).find(@parameters['queue_id'])
      Pundit.authorize(context.to_h, @assignee_queue, :show?)
      raise ArgumentError, 'Queue/team mismatch' if @parameters['team_id'] && @assignee_queue.team_id != @parameters['team_id']
    end
  end

  def collection
    records = MODELS.key?(resource) ? scoped_catalog : scoped_native
    records = authorized_records(records)
    if records.is_a?(Array)
      { items: records.slice(parameters.offset, parameters.per_page) || [],
        meta: { total: records.length, page: parameters.page, per_page: parameters.per_page } }
    else
      { items: records.offset(parameters.offset).limit(parameters.per_page),
        meta: { total: records.count, page: parameters.page, per_page: parameters.per_page } }
    end
  end

  private

  def authorized_records(records)
    # Native per-record policies are deliberately evaluated before counting/pagination.
    # No total includes contacts/teams/users denied by their own policies.
    if resource == 'assignees'
      records.select do |membership|
        team_id = parameters['team_id'] || @assignee_queue&.team_id
        candidate = JrcServiceDesk::Ticket.new(account: context.account, unit_id: unit_id, queue_id: parameters['queue_id'], team_id: team_id)
        JrcServiceDesk::AssignmentEligibility.manual_domain?(membership, candidate)
      end
    elsif NATIVE.include?(resource) && resource != 'contracts'
      records.select { |record| Pundit.policy!(context.to_h, record).show? }
    else
      records
    end
  end

  def scoped_catalog
    model = MODELS.fetch(resource)
    Pundit.authorize(context.to_h, model, :index?)
    records = Pundit.policy_scope!(context.to_h, model).where(active: true)
    records = case resource
              when 'units' then records.where(id: @units.select(:id))
              when 'operator_companies' then records.where(id: @units.select(:operator_company_id))
              else records.where(unit_id: @units.select(:id))
              end
    search(records, model.table_name, 'name').order(name: :asc, id: :asc)
  end

  def scoped_native
    case resource
    when 'contracts'
      scoped_contracts
    when 'requesters'
      JrcServiceDesk::RequesterDirectory.new(context).scope(company_id: parameters['company_id'], query: parameters['q']).order(name: :asc, id: :asc)
    when 'teams'
      Pundit.authorize(context.to_h, Team, :index?)
      records = Team.where(account_id: context.account.id)
      if context.supervision_access.restricted?(unit_id)
        records = records.where(id: context.supervision_access.grants.map { |grant| grant[:team_id] })
      end
      search(records, 'teams', 'name').order(name: :asc, id: :asc)
    when 'assignees'
      records = JrcServiceDesk::UnitMembership.operational.where(account_id: context.account.id, unit_id: unit_id, active: true,
                                                                manual_assignment_enabled: true)
        .joins(account_user: :user).includes(account_user: :user)
      if parameters['team_id']
        team = Team.where(account_id: context.account.id).find(parameters['team_id'])
        Pundit.authorize(context.to_h, team, :show?)
        records = records.where(users: { id: TeamMember.where(team_id: team.id).select(:user_id) })
      end
      if parameters['queue_id']
        queue = JrcServiceDesk::Queue.where(account_id: context.account.id, unit_id: unit_id, active: true).find(parameters['queue_id'])
        Pundit.authorize(context.to_h, queue, :show?)
        raise ArgumentError, 'Queue/team mismatch' if parameters['team_id'] && queue.team_id != parameters['team_id']
      end
      if context.supervision_access.restricted?(unit_id)
        grants = context.supervision_access.grants
        grants = grants.select { |grant| grant[:queue_id] == parameters['queue_id'] } if parameters['queue_id']
        records = records.where(users: { id: TeamMember.where(team_id: grants.map { |grant| grant[:team_id] }).select(:user_id) })
      end
      search(records, 'users', 'name').order('users.name ASC', 'jrc_service_desk_unit_memberships.id ASC')
    end
  end

  def scoped_contracts
    search(JrcServiceDesk::CatalogueContracts.new(context).scope, 'jrc_crm_contracts', 'contract_number').order(contract_number: :asc, id: :asc)
  end

  def search(records, table, field)
    return records if parameters['q'].nil? || parameters['q'].empty?
    records.where("#{table}.#{field} ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(parameters['q'])}%")
  end
end
