# frozen_string_literal: true

# Internal domain commands only; CP2 introduces no controller/route/job.
class JrcServiceDesk::BaseService
  def initialize(user_context:)
    @native_context = user_context
  end

  protected

  attr_reader :context, :actor_membership

  def fresh_context!
    value = JrcServiceDesk::OperationalContext.new(@native_context)
    raise Pundit::NotAuthorizedError, 'Service Desk access denied' unless value.native_operator?

    value
  end

  def with_unit(unit_id, administrative: false)
    unit_id = JrcServiceDesk::Input.id(unit_id)
    JrcServiceDesk::Base.transaction do
      initial = fresh_context!
      # Shared identity locks prevent flag/AccountUser revocation during the command.
      Account.where(id: initial.account.id).lock('FOR SHARE').take!
      AccountUser.where(id: initial.account_user.id, account_id: initial.account.id, user_id: initial.user.id).lock('FOR SHARE').take!
      if initial.account_user.respond_to?(:custom_role_id) && initial.account_user.custom_role_id
        raise Pundit::NotAuthorizedError unless initial.account_user.respond_to?(:custom_role) && initial.account_user.custom_role
        initial.account_user.custom_role.class.where(id: initial.account_user.custom_role_id, account_id: initial.account.id).lock('FOR SHARE').take!
      end
      @context = fresh_context!
      # Serialize writes in one unit in this foundation; no global/account write mutex.
      scope = administrative && context.administrator? ? context.view_unit_scope : context.unit_scope
      unit = scope.lock('FOR UPDATE OF jrc_service_desk_units').find(unit_id)
      @acting_unit = unit
      JrcServiceDesk::OperatorCompany.where(account_id: context.account.id, id: unit.operator_company_id, active: true).lock('FOR SHARE').take!
      memberships = context.active_memberships.where(unit_id: unit.id).lock('FOR SHARE')
      @actor_membership = administrative && context.administrator? ? memberships.take : memberships.take!
      yield unit
    end
  end

  def with_ticket(ticket_id, query)
    ticket_id = JrcServiceDesk::Input.id(ticket_id)
    initial = fresh_context!
    candidate = JrcServiceDesk::TicketPolicy::Scope.new(initial.to_h, JrcServiceDesk::Ticket).resolve.find(ticket_id)
    with_unit(candidate.unit_id) do |unit|
      ticket = JrcServiceDesk::TicketPolicy::Scope.new(context.to_h, JrcServiceDesk::Ticket).resolve
        .where(unit_id: unit.id).lock.find(ticket_id)
      authorize!(ticket, query)
      yield ticket
    end
  end

  def authorize!(record, query)
    Pundit.authorize(context.to_h, record, query)
  end

  def reference(model, value, unit)
    return nil if value.nil?

    model.where(account_id: context.account.id, unit_id: unit.id, active: true).lock('FOR SHARE').find(JrcServiceDesk::Input.id(value))
  end

  def native_team(value)
    return nil if value.nil?

    team = Team.where(account_id: context.account.id).find(JrcServiceDesk::Input.id(value))
    authorize!(team, :show?)
    team
  end

  def assignee(value, unit)
    return nil if value.nil?

    result = JrcServiceDesk::UnitMembership.where(account_id: context.account.id, unit_id: unit.id, active: true,
                                                   account_user_id: JrcServiceDesk::Input.id(value)).lock('FOR SHARE').take!
    account_user = AccountUser.where(id: result.account_user_id, account_id: context.account.id).lock('FOR SHARE').take!
    if account_user.respond_to?(:custom_role_id) && account_user.custom_role_id
      raise ActiveRecord::RecordNotFound unless account_user.respond_to?(:custom_role) && account_user.custom_role
      account_user.custom_role.class.where(id: account_user.custom_role_id, account_id: context.account.id).lock('FOR SHARE').take!
    end
    target_context = JrcServiceDesk::OperationalContext.new(account: context.account, user: account_user.user, account_user: account_user)
    raise ActiveRecord::RecordNotFound, 'No eligible assignee in this unit' unless target_context.capability?(:tickets_view) && target_context.unit_allowed?(unit)

    result
  end

  def verify_version!(ticket, expected)
    return if ticket.lock_version == JrcServiceDesk::Input.version(expected)

    raise ActiveRecord::StaleObjectError.new(ticket, 'update')
  end

  def append_event!(ticket, type, data)
    JrcServiceDesk::TicketEvent.create!(account: context.account, unit: ticket.unit, ticket: ticket,
                                         actor_membership: actor_membership, event_type: type,
                                         data: JrcServiceDesk::CanonicalJson.normalize(data))
  end

  def text(value, nullable: false)
    return nil if value.nil? && nullable
    raise ArgumentError, 'Expected text' unless value.is_a?(String)

    value
  end
end
