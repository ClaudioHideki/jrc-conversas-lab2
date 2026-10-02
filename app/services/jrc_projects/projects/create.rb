module JrcProjects
  module Projects
    class Create
      DEFAULT_COLUMNS = [{ 'name' => 'A fazer', 'status_key' => 'backlog' }, { 'name' => 'Em andamento', 'status_key' => 'in_progress' }, { 'name' => 'Em validacao', 'status_key' => 'review' }, { 'name' => 'Concluido', 'status_key' => 'completed' }].freeze
      def self.call(account:, actor:, attributes:, template: nil, idempotency_key:, origin: {}, correlation_id: nil)
        membership = account.account_users.find_by!(user_id: actor.id)
        raise Pundit::NotAuthorizedError unless Authorization.allowed?(account_user: membership, capability: 'projects.project.create')
        values = attributes.to_h.symbolize_keys.slice(:key, :name, :description, :visibility, :contact_id, :starts_on, :due_on, :priority)
        if account.feature_enabled?('jrc_customer_master') && attributes.to_h.symbolize_keys.key?(:company_id)
          values[:company_id] = attributes.to_h.symbolize_keys[:company_id]
          if values[:company_id].present?
            Pundit.authorize(JrcOperations::Access.user_context(membership), :directory, :access?, policy_class: JrcCustomers::DirectoryPolicy)
            values[:company_id] = JrcCustomers::CompanyLinkDecision.resolve(explicit: values[:company_id])
            values[:company_id] = JrcCustomers::Company.where(account_id: account.id).find(values[:company_id]).id
          end
        end
        source = origin.to_h.symbolize_keys.compact_blank
        raise ArgumentError, 'Escolha apenas uma origem para a criacao.' if source.values.count(&:present?) > 1
        raise ActiveRecord::RecordNotFound if template && template.account_id != account.id
        # Check source access even when an idempotency key replays an existing project.
        JrcOperations::Access.ticket!(membership, source[:ticket_id], write: true) if source[:ticket_id]
        JrcOperations::Access.deal!(membership, source[:deal_id], won: true, write: true) if source[:deal_id]
        JrcOperations::Access.conversation!(membership, source[:conversation_display_id]) if source[:conversation_display_id]
        JrcOperations::Idempotency.run(account: account, actor: actor, model: Project, key: idempotency_key, attributes: { project: values, template_id: template&.id, origin: source }) do |key, fingerprint|
          deal = JrcOperations::Access.deal!(membership, source[:deal_id], won: true, write: true, lock: true) if source[:deal_id]
          ticket = JrcOperations::Access.ticket!(membership, source[:ticket_id], write: true, lock: true) if source[:ticket_id]
          conversation = JrcOperations::Access.conversation!(membership, source[:conversation_display_id]) if source[:conversation_display_id]
          source_contact = deal&.contact || ticket&.requester || conversation&.contact
          if source_contact
            raise ArgumentError, 'O cliente deve ser o mesmo da origem.' if values[:contact_id].present? && values[:contact_id].to_i != source_contact.id
            values[:contact_id] = source_contact.id
          end
          JrcOperations::Access.contact!(membership, values[:contact_id]) if values[:contact_id].present?
          if account.feature_enabled?('jrc_customer_master')
            values[:company_id] = JrcCustomers::CompanyLinkDecision.resolve(
              explicit: values[:company_id], candidates: [deal&.company_id, ticket&.company_id, source_contact&.company_id]
            )
          end
          definition = template&.definition || {}
          raise ArgumentError, 'Modelo invalido.' unless definition.is_a?(Hash)
          columns = Array(definition['columns']).presence || DEFAULT_COLUMNS
          raise ArgumentError, 'Modelo limitado a 12 colunas e 200 tarefas.' if columns.length > 12 || Array(definition['tasks']).length > 200
          values[:key] = values[:key].presence || "P#{Time.current.strftime('%y%m%d')}-#{SecureRandom.hex(3).upcase}"
          project = Project.create!(values.merge(account: account, owner: actor, idempotency_key: key, request_fingerprint: fingerprint, template_snapshot: definition.deep_dup))
          project.project_members.create!(account: account, user: actor, role: 'owner')
          board = project.boards.create!(account: account, name: definition['board_name'].presence || 'Execucao')
          columns.each_with_index do |column, index|
            status = { 'em_andamento' => 'in_progress', 'concluido' => 'completed' }.fetch(column['status_key'], column['status_key'])
            raise ArgumentError, 'Status de coluna invalido no modelo.' unless Task::STATUSES.include?(status)
            board.board_columns.create!(account: account, name: column.fetch('name'), status_key: status, position: index)
          end
          first_column = board.board_columns.order(:position).first!
          raise ArgumentError, 'Primeira coluna deve ser A fazer.' unless first_column.status_key == 'backlog'
          Array(definition['tasks']).each_with_index do |task, index|
            raise ArgumentError, 'Tarefa do modelo invalida.' unless task.is_a?(Hash)
            due = task['due_offset_days'].present? ? (project.starts_on || Date.current) + Integer(task['due_offset_days']) : project.due_on
            project.tasks.create!(account: account, created_by: actor, title: task.fetch('title'), description: task['description'], estimated_minutes: task.fetch('estimated_minutes', 0), due_on: due, board_column: first_column, status: first_column.status_key, position: (index + 1) * 1024)
          end
          if source.any?
            JrcOperations::Linker.new(account_user: membership, correlation_id: correlation_id)
                                 .create!(attributes: source.merge(project_id: project.id))
            origin_action = deal ? 'projects.project.created_from_deal' : ticket ? 'projects.project.created_from_ticket' : 'projects.project.created_from_conversation'
            AuditEvent.record!(account: account, actor: actor, action: origin_action, auditable: project,
                               after_data: { origin: source }, correlation_id: correlation_id)
          end
          AuditEvent.record!(account: account, actor: actor, action: 'projects.project.created', auditable: project, after_data: { key: project.key, origin: source, priority: project.priority }, correlation_id: correlation_id)
          project
        end
      end
    end
  end
end
