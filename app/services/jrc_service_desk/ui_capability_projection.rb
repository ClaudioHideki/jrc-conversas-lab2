# frozen_string_literal: true

class JrcServiceDesk::UiCapabilityProjection
  def initialize(context)
    @context = context
  end

  def call
    resources = JrcServiceDesk::UiContextService::RESOURCES.transform_values { |model| index(model) }
    resources.merge(lookups, administrative, operations)
  end

  private

  def index(model)
    { index: Pundit.policy!(@context.to_h, model).index? }
  end

  def lookups
    { 'requesters' => { index: @context.capability?(:customers_view) && @context.capability?(:lookups_view) &&
      Pundit.policy!(@context.to_h, Contact).index? },
      'teams' => { index: @context.capability?(:lookups_view) && Pundit.policy!(@context.to_h, Team).index? },
      'assignees' => { index: JrcServiceDesk::LookupPolicy.new(@context.to_h, :lookup).index? },
      'contracts' => { index: @context.capability?(:lookups_view) && @context.capability?(:customers_view) &&
        JrcCustomers::Visibility.new(account: @context.account, user: @context.user, account_user: @context.account_user).crm? } }
  end

  def administrative
    policy = @context.capability?(:lifecycle_policies_manage)
    { 'module' => { index: true }, 'dashboard' => { index: @context.capability?(:dashboard_view) },
      'settings' => { index: @context.capability?(:settings_view) }, 'notifications' => { manage: @context.capability?(:notifications_manage) },
      'lifecycle_policies' => { index: policy, publish: policy }, 'configuration' => configuration,
      'operational_rules' => JrcServiceDesk::OperationalRuleContract::KINDS
        .index_with { |kind| JrcServiceDesk::OperationalRuleAccess.allowed?(@context, kind) },
      'operational_reports' => { index: @context.capability?(:dashboard_view) && @context.capability?(:tickets_view_all) } }
  end

  def configuration
    JrcServiceDesk::ConfigurationResources::MODELS.transform_values { |model| Pundit.policy!(@context.to_h, model).manage_index? }
  end

  def operations
    services = { index: @context.capability?(:lookups_view), create: @context.capability?(:services_manage) }
    { 'services' => services, 'catalog' => services, 'reports' => { index: @context.capability?(:dashboard_view) },
      'sla' => { index: @context.capability?(:dashboard_view) && @context.capability?(:sla_view) },
      'surveys' => { index: @context.capability?(:tickets_view) && @context.capability?(:customers_view) &&
        JrcRelationship::ModulePolicy.new(@context.to_h, @context.account).access? },
      'automations' => { index: @context.capability?(:settings_view) &&
        %i[lifecycle_policies_manage notifications_manage queues_manage priorities_manage incidents_manage]
          .any? { |key| @context.capability?(key) } },
      'tasks' => index(JrcServiceDesk::TicketTask), 'approvals' => index(JrcServiceDesk::TicketApproval),
      'incidents' => index(JrcServiceDesk::Incident), 'problems' => index(JrcServiceDesk::Incident),
      'changes' => index(JrcServiceDesk::OperationalResource), 'assets' => index(JrcServiceDesk::OperationalResource) }
  end
end
