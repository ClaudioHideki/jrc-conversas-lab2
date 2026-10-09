# Context projections retain the operator session's native scopes and result provenance.
class JrcNico::OperatorContext
  def initialize(access:, session:, selected:, notice: nil)
    @access = access
    @session = session
    @selected = selected
    @notice = notice
  end

  def self.command_context(workflow, conversation_id, route_name)
    { workflow_id: workflow, conversation_id: conversation_id.presence&.to_i,
      route_name: JrcCopilot::TaskCatalog::ROUTE_GUIDES.key?(route_name) ? route_name : nil }.compact
  end

  def self.continuation_context(previous)
    previous.execution_context.slice('workflow_id', 'conversation_id', 'route_name').merge('continuation_of' => previous.id)
  end

  def self.access_digest(access)
    fields = ['resource_provenance_v2', access.membership.attributes.slice('role', 'crm_enabled', 'custom_role_id'),
              access.membership.try(:custom_role)&.attributes, access.crm?, access.campaigns?,
              access.user.inboxes.pluck(:id).sort, access.user.teams.pluck(:id).sort]
    Digest::SHA256.hexdigest(fields.to_json)
  end

  def self.contact_rows(data)
    Array(data).map do |row|
      "##{row['id']} #{row['name']} (#{row['phone_number'].presence || row['email'].presence || 'sem telefone/email'})"
    end
  end

  def self.execution_context(command, tool, resources, ids, source_tool)
    command.execution_context.merge(
      'resources' => (Array(command.execution_context['resources']) + resources).uniq,
      'source_tools' => (Array(command.execution_context['source_tools']) + (source_tool ? [tool] : [])).uniq,
      'conversation_ids' => (Array(command.execution_context['conversation_ids']) + ids).uniq
    )
  end

  def remember_selection!
    return unless @selected

    @session.with_lock do
      ids = (Array(@session.context['conversation_ids']) + [@selected.display_id]).uniq
      @session.update!(context: @session.context.merge('conversation_ids' => ids))
    end
  end

  def selected_conversation
    @selected && { conversation_id: @selected.display_id, contact_id: @selected.contact_id, name: @selected.contact.name,
                   email: @selected.contact.email, phone_number: @selected.contact.phone_number }
  end

  def linked_leads
    linked_records(JrcCrm::Lead, %i[id name status])
  end

  def linked_deals
    linked_records(JrcCrm::Deal, %i[id title status])
  end

  def history
    @notice ? [] : @session.messages.last(16).map { |message| message.slice('role', 'content') }
  end

  def tool_error(error)
    if error.is_a?(Pundit::NotAuthorizedError)
      'Ferramenta indisponível para este perfil. Escolha outra ferramenta presente em context.tools.'
    else
      error.message
    end
  end

  private

  def linked_records(model, fields)
    return [] unless @selected && @access.crm?

    @access.crm_scope(model).where(contact_id: @selected.contact_id).limit(20).map { |record| record.slice(*fields) }
  end
end
