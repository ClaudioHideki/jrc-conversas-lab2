# frozen_string_literal: true

# Interpretation of the NATIVE roles/CustomRole.permissions, never a second store.
# Defaults describe the existing native profiles, not an administrator bypass.
class JrcServiceDesk::Capabilities
  PREFIX = 'jrc_service_desk_'
  KEYS = %w[notifications_manage customer_publish technical_notes tasks_view tasks_manage approvals_view approvals_request approvals_decide
            incidents_manage tickets_claim module_view tickets_view tickets_view_all tickets_create tickets_edit tickets_assign tickets_transfer
            priority_change work_status_change pause resume resolve close cancel reopen notes_view notes_add history_view conversations_view
            conversations_link sla_view contract_conditions_view sla_snapshots_record lookups_view customers_view queues_manage categories_manage
            priorities_manage statuses_manage services_manage lifecycle_policies_manage settings_view dashboard_view structure_view
            operator_companies_manage units_manage unit_memberships_manage].freeze
  PERMISSIONS = KEYS.map { |key| "#{PREFIX}#{key}" }.freeze
  DEFAULTS = {
    'agent' => %w[technical_notes tasks_view tasks_manage approvals_view approvals_request approvals_decide
                  tickets_claim module_view tickets_view
                  tickets_create tickets_edit tickets_assign tickets_transfer priority_change work_status_change pause resume resolve close cancel
                  reopen notes_view notes_add history_view conversations_view conversations_link sla_view lookups_view customers_view
                  dashboard_view].freeze,
    'administrator' => %w[notifications_manage customer_publish technical_notes tasks_view tasks_manage approvals_view approvals_request
                          approvals_decide incidents_manage tickets_claim structure_view operator_companies_manage units_manage
                          unit_memberships_manage
                          module_view tickets_view tickets_view_all tickets_create tickets_edit tickets_assign tickets_transfer priority_change
                          work_status_change pause resume resolve close cancel reopen notes_view notes_add history_view conversations_view
                          conversations_link sla_view contract_conditions_view sla_snapshots_record lookups_view customers_view queues_manage
                          categories_manage priorities_manage statuses_manage services_manage lifecycle_policies_manage settings_view
                          dashboard_view].freeze
  }.freeze
  DEPENDENCIES = {
    'notifications_manage' => %w[settings_view customer_publish].freeze,
    'customer_publish' => %w[notes_add].freeze,
    'technical_notes' => %w[notes_view].freeze,
    'tasks_view' => %w[tickets_view].freeze,
    'tasks_manage' => %w[tasks_view].freeze,
    'approvals_view' => %w[tickets_view].freeze,
    'approvals_request' => %w[approvals_view].freeze,
    'approvals_decide' => %w[approvals_view].freeze,
    'incidents_manage' => %w[tickets_view history_view].freeze,
    'tickets_claim' => %w[tickets_view tickets_assign].freeze,
    'operator_companies_manage' => %w[structure_view].freeze,
    'units_manage' => %w[structure_view].freeze,
    'unit_memberships_manage' => %w[structure_view].freeze,
    'tickets_view' => %w[module_view].freeze,
    'tickets_view_all' => %w[tickets_view].freeze,
    'tickets_create' => %w[tickets_view lookups_view customers_view].freeze,
    'tickets_edit' => %w[tickets_view].freeze,
    'tickets_assign' => %w[tickets_view].freeze,
    'tickets_transfer' => %w[tickets_view].freeze,
    'priority_change' => %w[tickets_view].freeze,
    'work_status_change' => %w[tickets_view history_view sla_view].freeze,
    'pause' => %w[tickets_view history_view sla_view].freeze,
    'resume' => %w[tickets_view history_view sla_view].freeze,
    'resolve' => %w[tickets_view history_view sla_view].freeze,
    'close' => %w[tickets_view history_view sla_view].freeze,
    'cancel' => %w[tickets_view history_view sla_view].freeze,
    'reopen' => %w[tickets_view history_view sla_view].freeze,
    'notes_view' => %w[tickets_view].freeze,
    'notes_add' => %w[notes_view].freeze,
    'history_view' => %w[tickets_view].freeze,
    'conversations_view' => %w[tickets_view].freeze,
    'conversations_link' => %w[conversations_view].freeze,
    'sla_view' => %w[tickets_view].freeze,
    'contract_conditions_view' => %w[sla_view].freeze,
    'sla_snapshots_record' => %w[contract_conditions_view].freeze,
    'lookups_view' => %w[module_view].freeze,
    'customers_view' => %w[tickets_view].freeze,
    'queues_manage' => %w[settings_view lookups_view].freeze,
    'categories_manage' => %w[settings_view lookups_view].freeze,
    'priorities_manage' => %w[settings_view lookups_view].freeze,
    'statuses_manage' => %w[settings_view lookups_view].freeze,
    'services_manage' => %w[settings_view lookups_view].freeze,
    'lifecycle_policies_manage' => %w[settings_view lookups_view].freeze,
    'settings_view' => %w[module_view].freeze,
    'dashboard_view' => %w[tickets_view].freeze,
  }.freeze
  LIFECYCLE_ACTIONS = {
    'work_status' => 'work_status_change', 'pause' => 'pause', 'resume' => 'resume',
    'resolve' => 'resolve', 'close' => 'close', 'cancel' => 'cancel', 'reopen' => 'reopen'
  }.freeze

  def initialize(native_role: nil, custom: false, permissions: [])
    @grants = if custom
                Array(permissions).select { |key| key.is_a?(String) && PERMISSIONS.include?(key) }.map { |key| key.delete_prefix(PREFIX) }
              else
                DEFAULTS.fetch(native_role, [])
              end
  end

  def allowed?(key)
    key = key.to_s
    KEYS.include?(key) && @grants.include?(key) && DEPENDENCIES.fetch(key, []).all? { |dependency| allowed?(dependency) }
  end

  def effective
    KEYS.select { |key| allowed?(key) }
  end
end
