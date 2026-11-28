# frozen_string_literal: true

class JrcServiceDesk::UiContextService
  RESOURCES = JrcServiceDesk::CatalogQuery::MODELS.merge('tickets' => JrcServiceDesk::Ticket).freeze
  def initialize(user_context:)
    @context = JrcServiceDesk::OperationalContext.new(user_context)
  end

  def call
    Pundit.authorize(@context.to_h, :service_desk, :show?, policy_class: JrcServiceDesk::ModulePolicy)
    visible = @context.view_unit_scope.includes(:operator_company).order(:name, :id).to_a
    ids = visible.map(&:id)
    initial = initial_statuses(ids)
    operational = @context.unit_scope.where(id: ids).pluck(:id).to_set
    assignable = assignable_unit_ids(ids)
    units = visible.map { |unit| unit_payload(unit, initial[unit.id], operational.include?(unit.id), assignable.include?(unit.id)) }
    capabilities = JrcServiceDesk::UiCapabilityProjection.new(@context).call
    effective_permissions = @context.effective_capabilities.map { |key| "#{JrcServiceDesk::Capabilities::PREFIX}#{key}" }
    { contract_version: 1, account_id: @context.account.id.to_s, user_id: @context.user.id.to_s,
      available: true, units: units, capabilities: capabilities, effective_permissions: effective_permissions }
  end

  private

  def initial_statuses(ids)
    return {} if ids.empty? || !@context.capability?(:lookups_view)

    JrcServiceDesk::TicketStatus.where(account_id: @context.account.id, unit_id: ids, initial: true, active: true, phase: 'open').index_by(&:unit_id)
  end

  def assignable_unit_ids(ids)
    return Set.new if ids.empty? || !@context.capability?(:tickets_assign)

    @context.active_memberships.operational.where(unit_id: ids, manual_assignment_enabled: true).distinct.pluck(:unit_id).to_set
  end

  def unit_payload(unit, initial, operational, assignable)
    permissions = unit_permissions(unit, operational)
    { id: unit.id.to_s, account_id: @context.account.id.to_s, name: unit.name, active: true,
      operator_company: { id: unit.operator_company.id.to_s, account_id: unit.account_id.to_s, name: unit.operator_company.name },
      initial_status: initial ? { id: initial.id.to_s, name: initial.name } : nil, permissions: permissions,
      internal_intake: permissions[:create_ticket] ? JrcServiceDesk::InternalIntake.presentation(unit, @context) : nil,
      self_assignee: assignable ? { id: @context.account_user.id.to_s, name: @context.user.name } : nil,
      employee_only: JrcServiceDesk::EmployeeAccess.restricted?(@context) }
  end

  def unit_permissions(unit, operational)
    candidate = JrcServiceDesk::Ticket.new(account: @context.account, unit: unit)
    { create_ticket: Pundit.policy!(@context.to_h, candidate).create?,
      assign_ticket: operational && @context.capability?(:tickets_assign),
      link_conversation: operational && @context.capability?(:conversations_link),
      manage_services: @context.capability?(:services_manage), manage_lifecycle_policies: @context.capability?(:lifecycle_policies_manage) }
  end
end
