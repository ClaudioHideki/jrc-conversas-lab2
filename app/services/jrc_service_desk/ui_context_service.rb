# frozen_string_literal: true

class JrcServiceDesk::UiContextService
  RESOURCES = JrcServiceDesk::CatalogQuery::MODELS.merge('tickets' => JrcServiceDesk::Ticket).freeze
  def initialize(user_context:)
    @context = JrcServiceDesk::OperationalContext.new(user_context)
  end

  def call
    Pundit.authorize(@context.to_h, :service_desk, :show?, policy_class: JrcServiceDesk::ModulePolicy)
    units = @context.view_unit_scope.includes(:operator_company).order(:name, :id).map do |unit|
      initial = @context.capability?(:lookups_view) && JrcServiceDesk::TicketStatus.find_by(account_id: @context.account.id, unit_id: unit.id, initial: true, active: true, phase: 'open')
      candidate = JrcServiceDesk::Ticket.new(account: @context.account, unit: unit)
      operational_unit = @context.unit_scope.exists?(id: unit.id)
      { id: unit.id.to_s, account_id: @context.account.id.to_s, name: unit.name, active: true,
        operator_company: { id: unit.operator_company.id.to_s, account_id: unit.account_id.to_s, name: unit.operator_company.name },
        initial_status: initial ? { id: initial.id.to_s, name: initial.name } : nil,
        permissions: { create_ticket: !!initial && Pundit.policy!(@context.to_h, candidate).create?,
                       assign_ticket: operational_unit && @context.capability?(:tickets_assign), link_conversation: operational_unit && @context.capability?(:conversations_link),
                       manage_services: @context.capability?(:services_manage), manage_lifecycle_policies: @context.capability?(:lifecycle_policies_manage) } }
    end
    capabilities = RESOURCES.to_h { |name, model| [name, { index: Pundit.policy!(@context.to_h, model).index? }] }
    capabilities['requesters'] = { index: @context.capability?(:customers_view) && @context.capability?(:lookups_view) && Pundit.policy!(@context.to_h, Contact).index? }
    capabilities['teams'] = { index: @context.capability?(:lookups_view) && Pundit.policy!(@context.to_h, Team).index? }
    capabilities['assignees'] = { index: JrcServiceDesk::LookupPolicy.new(@context.to_h, :lookup).index? }
    capabilities['module'] = { index: true }
    capabilities['dashboard'] = { index: @context.capability?(:dashboard_view) }
    capabilities['settings'] = { index: @context.capability?(:settings_view) }
    capabilities['lifecycle_policies'] = { index: @context.capability?(:lifecycle_policies_manage), publish: @context.capability?(:lifecycle_policies_manage) }
    capabilities['services'] = { index: @context.capability?(:lookups_view), create: @context.capability?(:services_manage) }
    capabilities['configuration'] = JrcServiceDesk::ConfigurationResources::MODELS.to_h { |name, model| [name, Pundit.policy!(@context.to_h, model).manage_index?] }
    capabilities['reports'] = { index: false } # No operational report API has been delivered.
    effective_permissions = @context.effective_capabilities.map { |key| "#{JrcServiceDesk::Capabilities::PREFIX}#{key}" }
    { contract_version: 1, account_id: @context.account.id.to_s, user_id: @context.user.id.to_s,
      available: true, units: units, capabilities: capabilities, effective_permissions: effective_permissions }
  end
end
