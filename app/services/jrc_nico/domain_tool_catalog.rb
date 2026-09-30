class JrcNico::DomainToolCatalog
  # These are finite commands, never model-provided routes, Ruby names or HTTP verbs.
  TOOLS = {
    'service_desk_context' => ['Consultar unidades, estado inicial e capacidades reais do Service Desk R2', 'service_desk', false, []],
    'service_desk_lookup' => ['Consultar página de catálogo R2 sem total: units/operator_companies/queues/priorities/categories/statuses/assignees/requesters/teams; nativos exigem unidade', 'service_desk', false, %w[resource* unit_id operator_company_id q page]],
    'list_service_tickets' => ['Listar página de até 20 chamados R2 autorizados, sem total da conta, com versão atual para alterações', 'service_desk', false, %w[unit_id status_id priority_id category_id queue_id assignee_id q mine page]],
    'read_service_ticket' => ['Consultar chamado R2 e permissões atuais', 'service_desk', false, %w[ticket_id*]],
    'create_service_ticket' => ['Criar chamado R2 na unidade explícita; consulte os IDs de solicitante, estado inicial e prioridade. conversation_id é display_id da conversa', 'service_desk', true, %w[unit_id* title* requester_id* status_id* priority_id* description category_id queue_id team_id assignee_account_user_id service_id conversation_id]],
    'update_service_ticket' => ['Alterar título, descrição, prioridade ou categoria R2 usando a versão consultada', 'service_desk', true, %w[ticket_id* expected_lock_version* title description priority_id category_id]],
    'assign_service_ticket' => ['Atribuir chamado R2 a operador, fila ou equipe na mesma unidade', 'service_desk', true, %w[ticket_id* expected_lock_version* assignee_account_user_id queue_id team_id]],
    'transfer_service_ticket' => ['Transferir atribuição R2 dentro da mesma unidade, sob permissão específica', 'service_desk', true, %w[ticket_id* expected_lock_version* assignee_account_user_id queue_id team_id]],
    'add_service_ticket_note' => ['Registrar nota interna no chamado R2', 'service_desk', true, %w[ticket_id* body*]],
    'read_service_ticket_lifecycle' => ['Consultar opções reais de ciclo de vida, requisitos, SLA, versões R2 e página de histórico sem total', 'service_desk', false, %w[ticket_id* page]],
    'transition_service_ticket' => ['Aplicar somente regra retornada pelo ciclo de vida R2; exige versões consultadas e evidências da regra', 'service_desk', true, %w[ticket_id* rule_key* expected_lock_version* expected_policy_version_id* reason_code note solution evidence_note_ids fields]],
    'link_service_ticket_conversation' => ['Vincular conversa visível ao chamado R2; conversation_id é display_id, não ID interno', 'service_desk', true, %w[ticket_id* conversation_id*]],
    'list_projects' => ['Consultar até 20 projetos visíveis por nome e estado', 'projects', false, %w[query status page]],
    'read_project' => ['Consultar projeto, versões, colunas e capacidades atuais', 'projects', false, %w[project_id*]],
    'list_project_tasks' => ['Consultar até 20 tarefas autorizadas do projeto e suas versões', 'projects', false, %w[project_id* status page]],
    'read_project_task' => ['Consultar tarefa autorizada, prazo, responsável e versão', 'projects', false, %w[project_id* task_id*]],
    'create_project' => ['Criar projeto interno ou de uma única origem explícita: negócio ganho, chamado R2 ou conversa; não cria contato', 'projects_create', true, %w[name* key description visibility contact_id starts_on due_on priority template_id deal_id ticket_id conversation_id]],
    'update_project' => ['Atualizar projeto com lock_version consultado; conclusão exige aceite e tarefas concluídas/canceladas', 'projects', true, %w[project_id* lock_version* name description status visibility contact_id owner_id starts_on due_on acceptance_notes priority]],
    'move_project_task' => ['Mover tarefa para coluna real do projeto com lock_version consultado; respeita WIP e dependências', 'projects', true, %w[project_id* task_id* column_id* lock_version* before_task_id]],
    'read_operations_agenda' => ['Consultar até 50 compromissos autorizados de CRM e Projetos, até 366 dias; reduza período para ver os demais. Service Desk não fornece tarefas à agenda', 'operations', false, %w[from to source view user_id]],
    'read_operation_links' => ['Consultar amostra autorizada sem totais: até 30 chamados, 30 projetos e 100 relações; exatamente uma origem: projeto, chamado, negócio, contato ou conversa', 'operations', false, %w[project_id ticket_id deal_id contact_id conversation_id]],
    'link_project_record' => ['Vincular projeto a chamado, tarefa, negócio ganho ou conversa, revalidando ambos os lados', 'projects', true, %w[project_id* ticket_id task_id deal_id conversation_id]],
    'unlink_project_record' => ['Remover vínculo existente de um projeto; informe link_id e exatamente uma origem: project_id, ticket_id ou deal_id', 'projects', true, %w[link_id* project_id ticket_id deal_id]],
    'list_sales_orders' => ['Consultar até 20 pedidos no escopo comercial autorizado', 'crm', false, %w[status page]],
    'read_sales_order' => ['Consultar pedido autorizado e valores registrados', 'crm', false, %w[sales_order_id*]],
    'convert_proposal_to_order' => ['Criar ou reutilizar pedido a partir de proposta aceita, preservando condições financeiras aceitas', 'crm', true, %w[proposal_id*]],
    'list_contracts' => ['Consultar até 20 contratos autorizados; não envia a provedor de assinatura', 'crm', false, %w[status page]],
    'read_contract' => ['Consultar vigência e estado de assinatura do contrato autorizado', 'crm', false, %w[contract_id*]],
    'list_commissions' => ['Consultar até 20 comissões no escopo do operador; não libera nem paga', 'crm', false, %w[status page]],
    'list_backoffice_requests' => ['Consultar até 20 solicitações de backoffice autorizadas', 'crm', false, %w[status page]],
    'read_backoffice_request' => ['Consultar etapa, estado e prazo da solicitação de backoffice autorizada', 'crm', false, %w[backoffice_request_id*]],
    'list_sales_goals' => ['Administrador CRM: consultar até 20 metas e progresso calculado pelo módulo', 'crm_admin', false, %w[status page]],
    'list_commission_programs' => ['Administrador CRM: consultar até 20 programas de comissão cadastrados', 'crm_admin', false, %w[page]]
  }.freeze

  def self.valid_value?(key, value)
    case key
    when 'expected_lock_version', 'lock_version' then value.is_a?(Integer) && value.between?(0, (2**53) - 1)
    when 'evidence_note_ids' then value.is_a?(Array) && value.size <= 30 && value.all? { |id| id.is_a?(Integer) && id.positive? }
    when 'fields'
      value.is_a?(Hash) && value.size <= 30 && value.all? do |field, entry|
        field.is_a?(String) && field.length <= 100 &&
          ((entry.is_a?(String) && entry.length <= 4000) || (entry.is_a?(Numeric) && entry.finite?) || [true, false, nil].include?(entry))
      end
    when 'user_id' then value == 'all' || (value.is_a?(Integer) && value.positive?)
    when 'mine' then value == 'true'
    else nil
    end
  end
end
