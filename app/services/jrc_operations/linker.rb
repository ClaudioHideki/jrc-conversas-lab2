module JrcOperations
  # Writes the existing Link relationship; never converts or copies its sources.
  class Linker
    def initialize(account_user:, correlation_id: nil)
      @member = account_user
      @account = account_user.account
      @actor = account_user.user
      @correlation_id = correlation_id
    end

    def create!(attributes:)
      values = attributes.to_h.symbolize_keys.slice(:project_id, :ticket_id, :task_id, :deal_id, :conversation_display_id).compact_blank
      @account.with_lock do
        project = values[:project_id] && Access.projects(@member).find(values[:project_id])
        with_project_lock(project) do
          records = resolve(values, project: project, write: true, require_won: true, lock: true)
          link_values = { project: nil, ticket: nil, task: nil, crm_deal: nil, conversation: nil }.merge(records).merge(account: @account)
          link = Link.find_by(link_values)
          unless link
            link = Link.create!(link_values.merge(created_by: @actor))
            audit!(link, link.task_id ? 'projects.task.linked' : link.ticket_id ? 'projects.ticket.linked' : link.crm_deal_id ? 'projects.deal.linked' : 'projects.conversation.linked')
          end
          link
        end
      end
    end

    def destroy!(id:, source:)
      @account.with_lock do
        link = Link.where(account_id: @account.id).find_by(id: id)
        replay = link.nil?
        if replay
          receipt = JrcProjects::AuditEvent.where(account_id: @account.id, action: 'projects.link.removed')
                                           .where("before_data ->> 'id' = ?", id.to_s).order(id: :desc).first!
          link = Link.new(receipt.before_data.slice('id', 'account_id', 'project_id', 'task_id', 'ticket_id', 'crm_deal_id', 'conversation_id'))
        end
        context = source.to_h.symbolize_keys.slice(:project_id, :ticket_id, :deal_id).compact_blank
        raise ArgumentError, 'Informe um unico contexto de origem.' unless context.size == 1
        field, value = context.first
        field = :crm_deal_id if field == :deal_id
        raise ActiveRecord::RecordNotFound unless link.public_send(field).to_s == value.to_s
        raise ArgumentError, 'Este vinculo nao pertence a um projeto.' unless link.project_id

        project = Access.projects(@member).find(link.project_id)
        project.with_lock do
          link.reload unless replay
          # Removing an existing CRM reference is allowed after its status changes.
          resolve(values_for(link), project: project, write: true, require_won: false, lock: true)
          return if replay
          audit!(link, 'projects.link.removed', removed: true)
          link.destroy!
        end
      end
    end

    def read(link)
      raise ActiveRecord::RecordNotFound unless link.account_id == @account.id
      resolve(values_for(link), write: false, require_won: false, lock: false)
    end

    def removable?(link)
      return false unless link.project_id && link.account_id == @account.id
      resolve(values_for(link), write: true, require_won: false, lock: false)
      true
    rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
      false
    end

    private

    def with_project_lock(project, &block)
      if project
        project.with_lock(&block)
      else
        yield
      end
    end

    def values_for(link)
      if link.conversation_id && link.conversation&.account_id != @account.id
        raise ActiveRecord::RecordNotFound
      end
      { project_id: link.project_id, task_id: link.task_id, ticket_id: link.ticket_id, deal_id: link.crm_deal_id,
        conversation_display_id: link.conversation&.display_id }.compact
    end

    def resolve(values, project: nil, write:, require_won:, lock:)
      raise ArgumentError, 'Informe o projeto. Conversas e chamados usam o vínculo nativo do Service Desk.' unless values[:project_id].present?
      records = {}
      if values[:project_id].present?
        raise Pundit::NotAuthorizedError unless Access.enabled?(@account, 'projects')
        project ||= Access.projects(@member).find(values[:project_id])
        capability = write ? 'projects.project.update' : 'projects.project.view'
        raise Pundit::NotAuthorizedError unless JrcProjects::Authorization.allowed?(account_user: @member, capability: capability, project: project)
        records[:project] = project
        if values[:task_id].present?
          scope = project.tasks.where(account_id: @account.id, project_id: project.id)
          task = (lock ? scope.lock : scope).find(values[:task_id])
          task_capability = write ? 'projects.task.update' : 'projects.task.view'
          unless JrcProjects::Authorization.allowed?(account_user: @member, capability: task_capability, project: project, record: task)
            raise Pundit::NotAuthorizedError
          end
          records[:task] = task
        end
      elsif values[:task_id].present?
        raise ArgumentError, 'Informe o projeto da tarefa.'
      end
      records[:ticket] = Access.ticket!(@member, values[:ticket_id], write: write, lock: lock) if values[:ticket_id].present?
      records[:crm_deal] = Access.deal!(@member, values[:deal_id], won: require_won, write: write, lock: lock) if values[:deal_id].present?
      if values[:conversation_display_id].present?
        records[:conversation] = Access.conversation!(@member, values[:conversation_display_id])
        records[:conversation].lock! if lock
      end
      records
    end

    def audit!(link, action, removed: false)
      return unless link.project
      payload = link.attributes.slice('id', 'account_id', 'project_id', 'task_id', 'ticket_id', 'crm_deal_id', 'conversation_id')
      JrcProjects::AuditEvent.record!(account: @account, actor: @actor, action: action, auditable: link.project,
                                     before_data: removed ? payload : {}, after_data: removed ? {} : payload,
                                     correlation_id: @correlation_id)
    end
  end
end
