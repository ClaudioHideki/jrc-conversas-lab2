class JrcNico::DelegationService
  def initialize(access)
    @access = access.authorize!
  end

  def start(args)
    unless @access.account.custom_attributes['nico_customer_delegation_enabled'] == true
      raise ArgumentError, 'O NICO desta conta atua como assistente interno.'
    end

    hours = args.fetch('hours', 2).clamp(1, 8)
    allowed_actions = args.fetch('allowed_actions', []).uniq
    raise ArgumentError, 'Autorização desconhecida.' if (allowed_actions - JrcNico::DelegatedActions::GROUPS.keys).any?
    crm = args['allow_crm'] == true || allowed_actions.include?('leads')
    raise Pundit::NotAuthorizedError if (crm || (allowed_actions & %w[proposals meetings]).any?) && !@access.crm?
    raise ArgumentError, 'Configure um provedor real para habilitar atendimento automático.' unless ENV['NICO_MODE'] == 'provider'

    conversations = args.fetch('conversation_ids').uniq.map { |id| @access.conversation(id) }
    bot = AgentBot.find_or_create_by!(account: @access.account, name: 'NICO Comercial') do |record|
      record.description = 'Assistente virtual comercial com atendimento delegado e supervisão humana'
    end
    conversations.map do |conversation|
      conversation.with_lock do
        if conversation.assignee_agent_bot_id.present? || JrcFlows::Access.inbox_bot_owned?(conversation) ||
           JrcFlowRun.live.exists?(account_id: @access.account.id, conversation_id: conversation.id)
          raise ArgumentError, 'Esta conversa já pertence a um bot ou Flow. Preserve o executor atual antes de delegar atendimento.'
        end

        delegation = JrcNico::Delegation.find_or_initialize_by(conversation: conversation)
        raise ArgumentError, 'Esta conversa já está sob atendimento do NICO. Retome antes de alterar a delegação.' if delegation.persisted? && delegation.live?
        # Retain the delegating operator's authorized participation after bot assignment.
        unless @access.membership.administrator? || conversation.conversation_participants.exists?(user: @access.user)
          conversation.conversation_participants.create!(user: @access.user)
        end
        delegation.assign_attributes(account: @access.account, user: @access.user, agent_bot: bot,
                                     objective: args.fetch('objective'), allow_crm: crm, allowed_actions: allowed_actions, status: 'active', reason: nil,
                                     version: delegation.version.to_i + 1, expires_at: hours.hours.from_now,
                                     last_message_id: [delegation.last_message_id.to_i,
                                       conversation.messages.where(message_type: :outgoing, private: false).maximum(:id).to_i].max)
        delegation.save!
        Conversations::AssignmentService.new(conversation: conversation, assignee_id: bot.id, assignee_type: 'AgentBot').perform
        conversation.update!(status: 'pending', custom_attributes: conversation.custom_attributes.to_h.merge('nico_control' => 'active'))
        delegation.snapshot
      end
    end
  end

  def self.stop(conversation, reason:, user: nil, status: 'paused', summary: nil)
    conversation = Conversation.find(conversation.id)
    conversation.with_lock do
      delegation = JrcNico::Delegation.find_by(conversation: conversation)
      next unless delegation && (delegation.status == 'active' || (delegation.status == 'needs_human' && reason != 'commercial_handoff'))

      delegation.update!(status: status, reason: reason, version: delegation.version + 1, summary: summary || delegation.summary)
      # A queued automatic browser action must not outlive its delegation.
      JrcNico::Command.joins(:session).where(jrc_nico_sessions: { account_id: delegation.account_id, user_id: delegation.user_id })
        .where("execution_context #>> '{authorization,delegation_id}' = ?", delegation.id.to_s)
        .where(status: 'browser_pending').find_each do |command|
          command.update!(status: 'cancelled', reply: 'Ação automática cancelada: atendimento retomado ou delegação encerrada.')
        end
      if conversation.assignee_agent_bot_id == delegation.agent_bot_id
        conversation.assignee_agent_bot = nil
        recipient = user || delegation.user
        conversation.assignee = recipient if conversation.account.users.exists?(recipient.id)
      end
      conversation.status = 'open' if conversation.pending?
      conversation.custom_attributes = conversation.custom_attributes.to_h.merge('nico_control' => status)
      conversation.save!
      if reason != 'commercial_handoff' && (status == 'needs_human' || reason == 'expired')
        detail = reason == 'expired' ? 'O período de atendimento do NICO terminou.' : 'O NICO interrompeu o atendimento e precisa da sua intervenção.'
        JrcNico::Notice.publish!(account: delegation.account, user: delegation.user, conversation: conversation,
          event_key: "delegation:#{delegation.id}:#{delegation.version}:#{status}", kind: 'attention',
          body: "#{conversation.contact.name}: #{detail}")
      end
      delegation
    end
  end

  def self.delivery_allowed?(message)
    control = message.content_attributes.to_h['nico_delegation']
    return true unless control

    delegation = JrcNico::Delegation.find_by(id: control['id'], account_id: message.account_id, conversation_id: message.conversation_id)
    return false unless delegation && delegation.version == control['version'] && delegation.agent_bot_id == message.sender_id
    # The final handoff message is allowed only for its exact version and turn.
    state_allowed = (delegation.live? && delegation.conversation.pending? && delegation.conversation.assignee_agent_bot_id == delegation.agent_bot_id) ||
                    (delegation.status == 'needs_human' && control['handoff'] == true)
    return false unless state_allowed && delegation.expires_at > Time.current && delegation.account.custom_attributes['nico_enabled'] == true

    JrcNico::Access.new(account: delegation.account, user: delegation.user, conversation: delegation.conversation).authorize!
    true
  rescue Pundit::NotAuthorizedError
    false
  end
end
