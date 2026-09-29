class JrcProjects::Projects::Update
  FIELDS = %i[name description status visibility contact_id owner_id starts_on due_on acceptance_notes priority].freeze

  def self.call(account:, actor:, project:, attributes:, correlation_id:)
    membership = account.account_users.find_by!(user_id: actor.id)
    project = JrcOperations::Access.projects(membership).find(project.id)
    values = attributes.to_h.symbolize_keys.slice(*FIELDS, :lock_version)
    version = values.delete(:lock_version)
    raise ArgumentError, 'Informe a versao do registro (lock_version).' if version.nil?

    # Uses the same account lock as existing link creation, then the project lock.
    account.with_lock do
      project.with_lock do
        unless JrcProjects::Authorization.allowed?(account_user: membership, capability: 'projects.project.update', project: project)
          raise Pundit::NotAuthorizedError
        end
        raise ActiveRecord::StaleObjectError.new(project, 'update') unless project.lock_version == Integer(version)

        before = project.attributes.slice(*FIELDS.map(&:to_s)).merge('priority' => project.priority)
        if values.key?(:contact_id)
          values[:contact_id] = if values[:contact_id].present?
                                  JrcOperations::Access.contact!(membership, values[:contact_id]).id
                                end
        end
        previous_owner_id = project.owner_id
        if values.key?(:owner_id) && values[:owner_id].to_s != previous_owner_id.to_s
          unless JrcProjects::Authorization.allowed?(account_user: membership, capability: 'projects.project.transfer', project: project)
            raise Pundit::NotAuthorizedError
          end
          values[:owner_id] = account.users.find(values[:owner_id]).id
        end

        if values[:status] == 'completed' && project.status != 'completed'
          if project.tasks.where(account_id: account.id).where.not(status: %w[completed canceled]).exists?
            raise ArgumentError, 'Conclua ou cancele as tarefas pendentes antes do aceite.'
          end
          raise ArgumentError, 'Registre o aceite da entrega.' if values[:acceptance_notes].blank?

          project.accepted_by = actor
          project.completed_at = Time.current
        elsif values[:status].present? && values[:status] != 'completed'
          project.completed_at = nil
          project.accepted_by = nil
        end

        project.update!(values)
        if project.owner_id != previous_owner_id
          members = project.project_members.where(account_id: account.id, project_id: project.id)
          previous_member = members.find_by(user_id: previous_owner_id)
          previous_member.update!(role: 'manager') if previous_member&.role == 'owner'
          next_member = members.find_or_initialize_by(user_id: project.owner_id)
          next_member.update!(role: 'owner')
        end
        JrcProjects::AuditEvent.record!(
          account: account, actor: actor, action: 'projects.project.updated', auditable: project,
          before_data: before, after_data: project.attributes.slice(*FIELDS.map(&:to_s)).merge('priority' => project.priority),
          correlation_id: correlation_id
        )
      end
    end
    project
  end
end
