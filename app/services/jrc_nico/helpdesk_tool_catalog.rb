class JrcNico::HelpdeskToolCatalog
  TOOLS = {
    'read_service_ticket_tasks' => ['Consultar tarefas visíveis do chamado, sem totais globais', 'service_desk_helpdesk', false, %w[ticket_id* page]],
    'create_service_ticket_task' => ['Criar tarefa interna do chamado com prazo, responsável e checklist explícitos', 'service_desk_helpdesk', true,
                                     %w[ticket_id* title* description due_at priority assignee_account_user_id checklist]],
    'read_service_ticket_approvals' => ['Consultar aprovações internas visíveis do chamado; não decide pelo aprovador',
                                        'service_desk_helpdesk', false, %w[ticket_id* page]],
    'read_service_incident' => ['Consultar incidente nativo e chamados autorizados', 'service_desk_helpdesk', false, %w[incident_id*]],
    'create_service_incident' => ['Criar incidente nativo e vincular chamados autorizados da mesma unidade', 'service_desk_helpdesk', true,
                                  %w[unit_id* title* severity* description ticket_ids*]],
    'prepare_incident_campaign' => ['Prepare only a reviewed draft for the exact incident requester cohort; never launch',
      'service_desk_helpdesk', true, %w[event_id* incident_id* inbox_id* name* source_digest*]],
    'prepare_closed_case_knowledge' => ['Prepare an explicitly human-generalized private knowledge draft; never approve or publish',
      'service_desk_helpdesk', true, %w[event_id* closed_transition_id* title* body* generalization_reviewed* source_digest*]]
  }.freeze
  CAPABILITIES = {
    'read_service_ticket_tasks' => :tasks_view, 'create_service_ticket_task' => :tasks_manage,
    'read_service_ticket_approvals' => :approvals_view, 'read_service_incident' => :incidents_manage,
    'create_service_incident' => :incidents_manage, 'prepare_incident_campaign' => :incidents_manage,
    'prepare_closed_case_knowledge' => :history_view
  }.freeze
  BOOLEAN_VALUES = [true, false].freeze

  def self.available?(access, name)
    context = JrcServiceDesk::OperationalContext.new(account: access.account, user: access.user, account_user: access.membership)
    allowed = context.capability?(:module_view) && context.capability?(CAPABILITIES.fetch(name))
    allowed &&= context.administrator? if %w[prepare_incident_campaign prepare_closed_case_knowledge].include?(name)
    allowed &&= access.campaigns? if name == 'prepare_incident_campaign'
    allowed
  end

  def self.valid_value?(key, value)
    case key
    when 'generalization_reviewed' then value == true
    when 'source_digest' then value.is_a?(String) && value.match?(/\A[a-f0-9]{64}\z/)
    when 'ticket_ids' then ticket_ids?(value)
    when 'checklist' then checklist?(value)
    when 'severity' then %w[low normal high critical].include?(value)
    when 'priority' then %w[low normal high urgent].include?(value)
    when 'due_at' then date?(value)
    end
  rescue ArgumentError
    false
  end

  def self.ticket_ids?(value)
    value.is_a?(Array) && value.size.between?(1, 200) && value.uniq == value && value.all? { |id| id.is_a?(Integer) && id.positive? }
  end

  def self.checklist?(value)
    value.is_a?(Array) && value.size <= 100 && value.all? { |item| checklist_item?(item) }
  end

  def self.checklist_item?(item)
    item.is_a?(Hash) && item.keys.sort == %w[done title] && item['title'].is_a?(String) &&
      item['title'].strip.size.between?(1, 500) && BOOLEAN_VALUES.include?(item['done'])
  end

  def self.date?(value)
    value.is_a?(String) && value.size <= 60 && Time.iso8601(value).present?
  end
end
