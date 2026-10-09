# frozen_string_literal: true

class JrcServiceDesk::UiContextService
  RESOURCES = JrcServiceDesk::CatalogQuery::MODELS.merge('tickets' => JrcServiceDesk::Ticket).freeze
  def initialize(user_context:)
    @context = JrcServiceDesk::OperationalContext.new(user_context)
  end

  def call
    Pundit.authorize(@context.to_h, :service_desk, :show?, policy_class: JrcServiceDesk::ModulePolicy)
    units = @context.view_unit_scope.includes(:operator_company).order(:name, :id).map { |unit| unit_payload(unit) }
    capabilities = JrcServiceDesk::UiCapabilityProjection.new(@context).call
    effective_permissions = @context.effective_capabilities.map { |key| "#{JrcServiceDesk::Capabilities::PREFIX}#{key}" }
    { contract_version: 1, account_id: @context.account.id.to_s, user_id: @context.user.id.to_s,
      available: true, units: units, capabilities: capabilities, effective_permissions: effective_permissions }
  end

  private

  def initial_status(unit)
    @context.capability?(:lookups_view) && JrcServiceDesk::TicketStatus.find_by(account_id: @context.account.id, unit_id: unit.id,
                                                                                initial: true, active: true, phase: 'open')
  end

  def unit_payload(unit)
    initial = initial_status(unit)
    { id: unit.id.to_s, account_id: @context.account.id.to_s, name: unit.name, active: true,
      operator_company: { id: unit.operator_company.id.to_s, account_id: unit.account_id.to_s, name: unit.operator_company.name },
      initial_status: initial ? { id: initial.id.to_s, name: initial.name } : nil, permissions: unit_permissions(unit, initial) }
  end

  def unit_permissions(unit, initial)
    candidate = JrcServiceDesk::Ticket.new(account: @context.account, unit: unit)
    operational = @context.unit_scope.exists?(id: unit.id)
    { create_ticket: initial.present? && Pundit.policy!(@context.to_h, candidate).create?,
      assign_ticket: operational && @context.capability?(:tickets_assign),
      link_conversation: operational && @context.capability?(:conversations_link),
      manage_services: @context.capability?(:services_manage), manage_lifecycle_policies: @context.capability?(:lifecycle_policies_manage) }
  end
end
