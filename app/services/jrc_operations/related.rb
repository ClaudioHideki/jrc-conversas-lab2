module JrcOperations
  class Related
    def initialize(account_user:, source:)
      @member = account_user
      @account = account_user.account
      @source = source.to_h.symbolize_keys
    end
    def call
      return { tickets: [], projects: [], conversations: [], deals: [], task_links: [], relations: [], actions: {} } unless Access.ready?
      contexts = @source.slice(:ticket_id, :project_id, :deal_id, :contact_id, :conversation_display_id).compact_blank
      raise ArgumentError, 'Informe um unico contexto de origem.' unless contexts.size == 1
      tickets = Access.tickets(@member)
      projects = Access.enabled?(@account, 'projects') ? Access.projects(@member) : JrcProjects::Project.none
      links = Link.where(account_id: @account.id)
      matching = links.none
      source_record = nil
      conversation_ids = []
      deal_ids = []
      case
      when @source[:conversation_display_id].present?
        conversation = Access.conversation!(@member, @source[:conversation_display_id])
        direct = links.where(conversation_id: conversation.id)
        tickets = tickets.where(id: direct.select(:ticket_id)).or(tickets.where(id: JrcServiceDesk::TicketConversation.where(account_id: @account.id, conversation_id: conversation.id).select(:ticket_id)))
        projects = projects.where(id: direct.select(:project_id)).or(projects.where(id: links.where(ticket_id: tickets.select(:id)).select(:project_id)))
      when @source[:contact_id].present?
        contact = Access.contact!(@member, @source[:contact_id])
        source_record = contact
        tickets = tickets.where(requester_id: contact.id)
        projects = projects.where(contact_id: contact.id).or(projects.where(id: links.where(ticket_id: tickets.select(:id)).select(:project_id)))
      when @source[:ticket_id].present?
        ticket = Access.ticket!(@member, @source[:ticket_id])
        source_record = ticket
        matching = links.where(ticket_id: ticket.id)
        projects = projects.where(id: matching.select(:project_id))
        conversation_ids = ticket.ticket_conversations.where(account_id: @account.id).pluck(:conversation_id)
        tickets = tickets.none
      when @source[:project_id].present?
        project = projects.find(@source[:project_id])
        source_record = project
        matching = links.where(project_id: project.id)
        tickets = tickets.where(id: matching.select(:ticket_id))
        conversation_ids = matching.pluck(:conversation_id).compact
        deal_ids = matching.pluck(:crm_deal_id).compact
        projects = projects.none
      when @source[:deal_id].present?
        deal = Access.deal!(@member, @source[:deal_id])
        source_record = deal
        matching = links.where(crm_deal_id: deal.id)
        projects = projects.where(id: matching.select(:project_id))
        tickets = tickets.where(id: links.where(project_id: projects.select(:id)).select(:ticket_id))
      else
        raise ArgumentError, 'Informe o contexto do vinculo.'
      end
      data = {
        tickets: tickets.order(updated_at: :desc).limit(30).map { |ticket| ticket_payload(ticket) },
        projects: projects.order(updated_at: :desc).limit(30).map { |project| project.as_json(only: %i[id key name status contact_id]) },
        tickets_total: tickets.count, projects_total: projects.count,
        conversations: [], deals: [], task_links: [], relations: [], actions: actions_for(source_record)
      }
      @account.conversations.where(id: conversation_ids).includes(:inbox).each do |conversation|
        next unless ConversationPolicy.new(Access.user_context(@member), conversation).show?
        data[:conversations] << { id: conversation.display_id, inbox: conversation.inbox.name, status: conversation.status }
      end
      if Access.crm?(@member)
        scope = JrcCrm::Deal.where(account_id: @account.id, id: deal_ids)
        scope = scope.where(owner_id: @member.user_id) unless Access.admin?(@member)
        data[:deals] = scope.filter_map do |record|
          deal_payload(Access.deal!(@member, record.id))
        rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
          nil
        end
      end
      if @source[:ticket_id].present? || @source[:project_id].present? || @source[:deal_id].present?
        linker = Linker.new(account_user: @member)
        candidates = matching.where(project_id: Access.projects(@member).select(:id)).order(id: :desc).limit(100)
        data[:relations] = candidates.filter_map do |link|
          records = linker.read(link)
          {
            id: link.id, can_remove: linker.removable?(link),
            project: records[:project]&.as_json(only: %i[id key name status contact_id]),
            ticket: records[:ticket] && ticket_payload(records[:ticket]),
            task: records[:task]&.as_json(only: %i[id title status project_id]),
            deal: records[:crm_deal] && deal_payload(records[:crm_deal]),
            conversation: records[:conversation] && { id: records[:conversation].display_id },
            contact: contact_payload(records[:ticket]&.requester || records[:crm_deal]&.contact || records[:conversation]&.contact)
          }
        rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
          nil
        end
      end
      data[:task_links] = data[:relations].filter_map do |relation|
        next unless relation[:task] && relation[:ticket]
        { id: relation[:id], project_id: relation[:project]['id'], ticket_id: relation[:ticket]['id'],
          task_id: relation[:task]['id'], title: relation[:task]['title'] }
      end
      data
    end

    private

    def ticket_payload(ticket)
      { 'id' => ticket.id, 'number' => ticket.id, 'title' => ticket.title, 'status' => ticket.status.name,
        'requester_id' => ticket.requester_id, 'unit_id' => ticket.unit_id }
    end

    def actions_for(record)
      project_enabled = Access.enabled?(@account, 'projects')
      source_write = if record.is_a?(JrcServiceDesk::Ticket)
                       JrcServiceDesk::TicketPolicy.new(Access.r2_context(@member), record).update?
                     elsif record.is_a?(JrcProjects::Project)
                       JrcProjects::Authorization.allowed?(account_user: @member, capability: 'projects.project.update', project: record)
                     elsif record.is_a?(JrcCrm::Deal)
                       record.won? && JrcCrm::DealPolicy.new(Access.user_context(@member), record).update?
                     else
                       @source[:conversation_display_id].present?
                     end
      create_origin = @source[:ticket_id].present? || @source[:deal_id].present? || @source[:contact_id].present?
      {
        create_project: project_enabled && create_origin && (source_write || @source[:contact_id].present?) &&
          JrcProjects::Authorization.allowed?(account_user: @member, capability: 'projects.project.create'),
        link: source_write,
        link_project: project_enabled && source_write && (@source[:ticket_id].present? || @source[:deal_id].present?),
        link_task: project_enabled && source_write && @source[:ticket_id].present?,
        deal_won: record.is_a?(JrcCrm::Deal) ? record.won? : nil
      }
    end

    def contact_payload(contact)
      contact.as_json(only: %i[id name]) if contact && contact.account_id == @account.id
    end

    def deal_payload(deal)
      organization = @account.jrc_crm_organizations.find_by(id: deal.organization_id) if deal.organization_id
      company = JrcCrm::CompanyAdapter.resolve_entity(account: @account, company_id: deal.company_id) if deal.company_id
      deal.as_json(only: %i[id title status contact_id organization_id company_id]).merge(
        'contact' => contact_payload(deal.contact), 'organization' => organization&.as_json(only: %i[id name]),
        'company' => company&.as_json(only: %i[id name])
      )
    end
  end
end
