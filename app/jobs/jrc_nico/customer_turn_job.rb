class JrcNico::CustomerTurnJob < ApplicationJob
  queue_as :default

  def perform(delegation_id, capacity_attempt = 0)
    delegation = JrcNico::Delegation.find_by(id: delegation_id)
    return unless delegation

    conversation = delegation.conversation
    turn = claim(delegation, conversation)
    return unless turn

    self.class.set(wait: 2.minutes).perform_later(delegation_id)

    access = JrcNico::Access.new(account: delegation.account, user: delegation.user, conversation: conversation).authorize!
    incoming = conversation.messages.find(turn.message_id)
    result = JrcNico::OperationalInference.call(account: delegation.account, user: delegation.user, kind: 'customer',
                                               message: incoming.content.to_s.first(4000), context: customer_context(delegation, access))
    publish(delegation, conversation, turn, result)
  rescue JrcNico::RunCapacity::Exceeded
    turn&.destroy! # no provider request or customer effect occurred; retain the incoming cursor for a later attempt
    if delegation&.live?
      if capacity_attempt < 3
        self.class.set(wait: 30.seconds).perform_later(delegation_id, capacity_attempt + 1)
      else
        JrcNico::DelegationService.stop(conversation, reason: 'capacity_unavailable', status: 'needs_human')
      end
    end
  rescue StandardError => e
    Rails.logger.warn("NICO customer turn failed delegation_id=#{delegation_id} type=#{e.class.name} location=#{e.backtrace&.first}")
    turn&.update!(status: 'failed')
    JrcNico::DelegationService.stop(conversation, reason: 'attention_required', status: 'needs_human') if conversation
  end

  private

  def incoming_scope(conversation)
    conversation.messages.where(message_type: :incoming, private: false)
  end

  def claim(delegation, conversation)
    conversation.with_lock do
      delegation.reload
      unless delegation.live?
        JrcNico::DelegationService.stop(conversation, reason: 'expired') if delegation.status == 'active'
        next
      end
      unless conversation.pending? && conversation.assignee_agent_bot_id == delegation.agent_bot_id
        JrcNico::DelegationService.stop(conversation, reason: 'conversation_changed')
        next
      end
      running = delegation.turns.where(status: %w[running dispatching])
      if running.where('created_at < ?', 2.minutes.ago).exists?
        JrcNico::DelegationService.stop(conversation, reason: 'interrupted_turn', status: 'needs_human')
        next
      end
      next if running.exists?

      message = incoming_scope(conversation).where('id > ?', delegation.last_message_id).reorder(id: :desc).first
      next unless message
      if message.content.blank?
        JrcNico::DelegationService.stop(conversation, reason: 'attachment_needs_human', status: 'needs_human')
        next
      end
      next if delegation.turns.exists?(version: delegation.version, message_id: message.id)

      delegation.turns.create!(message_id: message.id, version: delegation.version)
    end
  end

  def customer_context(delegation, access)
    conversation = access.conversation
    {
      objective: delegation.objective,
      company: delegation.account.name,
      continuation: conversation.messages.outgoing.where(sender_type: 'AgentBot', sender_id: delegation.agent_bot_id).exists?,
      timezone: delegation.account.reporting_timezone.presence || Time.zone.name,
      today: Time.current.in_time_zone(delegation.account.reporting_timezone.presence || Time.zone.name).iso8601,
      pending_requests: JrcNico::Notice.where(conversation: conversation, user: delegation.user, kind: 'action')
                                     .where(status: %w[new planning awaiting_confirmation browser_pending executing unknown]).order(id: :desc).limit(5).pluck(:request),
      authorized_actions: delegation.allowed_actions,
      completed_actions: completed_actions(delegation),
      modules: JrcCopilot::TaskCatalog::ROUTE_GUIDES.transform_values { |guide| guide[:title] },
      conversation: conversation.messages.where(private: false, message_type: [:incoming, :outgoing]).reorder(id: :desc).limit(40).reverse.map do |m|
        { role: m.incoming? ? 'customer' : 'assistant', content: m.content.to_s.first(1000) }
      end,
      knowledge: JrcNico::KnowledgeDocument.where(account: delegation.account, customer_visible: true).approved.order(updated_at: :desc).limit(10)
                                         .map { |d| { title: d.title, body: d.body.first(2000) } },
      products: JrcNico::OperationalAccess.new(account: delegation.account, user: delegation.user).crm? ?
        delegation.account.jrc_crm_products.where(active: true).limit(30).map do |p|
          p.attributes.slice('name', 'description', 'unit_price_cents', 'currency', 'billing_model', 'minimum_quantity', 'scope_included', 'scope_excluded')
           .transform_values { |value| value.is_a?(String) ? value.first(1000) : value }
        end : []
    }
  end

  def completed_actions(delegation)
    access = JrcNico::OperationalAccess.new(account: delegation.account, user: delegation.user).authorize!
    JrcNico::Notice.where(conversation: delegation.conversation, user: delegation.user, kind: 'action')
      .order(id: :desc).limit(5).select { |notice| notice.visible_to?(access) }.flat_map do |notice|
        notice.commands.where(status: 'succeeded').where.not(tool: [nil, '']).filter_map do |command|
          next unless JrcNico::ToolCatalog::TOOLS.dig(command.tool, 2) == true
          # Customer-facing inference receives receipts, never internal notes or knowledge searches.
          record = command.result.fetch('record', {}).slice('id', 'name', 'title', 'status', 'due_at', 'total_cents', 'valid_until')
          { tool: command.tool, record: record, browser_status: command.result['browser_status'] }
        end
      end.last(10)
  end

  def publish(delegation, conversation, turn, result)
    conversation.with_lock do
      delegation.reload
      turn.reload
      unless delegation.live? && delegation.version == turn.version && conversation.pending? && conversation.assignee_agent_bot_id == delegation.agent_bot_id
        turn.update!(status: 'cancelled')
        next
      end
      JrcNico::Access.new(account: delegation.account, user: delegation.user, conversation: conversation).authorize!
      if incoming_scope(conversation).where('id > ?', turn.message_id).exists?
        turn.update!(status: 'superseded')
        self.class.set(wait: 2.seconds).perform_later(delegation.id)
        next
      end
      if result['mode'] != 'provider' || result['reply'].blank?
        turn.update!(status: 'failed')
        JrcNico::DelegationService.stop(conversation, reason: 'empty_or_simulated_reply', status: 'needs_human')
        next
      end
      if delegation.allow_crm? && result['create_lead']
        access = JrcNico::OperationalAccess.new(account: delegation.account, user: delegation.user).authorize!
        raise Pundit::NotAuthorizedError unless access.crm?
        lead_result = JrcCrm::ConversationLeadService.new(account: delegation.account, actor: delegation.user, conversation: conversation).call
        lead = lead_result.fetch(:lead)
        lead.update!(notes: result['summary']) if lead_result.fetch(:created) && result['summary'].present?
        JrcNico::Notice.publish!(account: delegation.account, user: delegation.user, conversation: conversation,
          event_key: "lead:#{conversation.id}:#{lead.id}", kind: 'opportunity', status: 'completed',
          body: "#{conversation.contact.name}: oportunidade registrada no CRM. Lead ##{lead.id}. #{result['summary'].to_s.first(1000)}",
          metadata: { resources: [['JrcCrm::Lead', lead.id]], tool: 'create_lead', route_name: 'crm_leads' })
      end
      request = result['operator_request'].to_s.strip.first(2000)
      if request.present?
        JrcNico::Notice.publish!(account: delegation.account, user: delegation.user, conversation: conversation,
          event_key: "action:#{turn.id}", kind: 'action', request: request, body: request,
          metadata: { message_id: turn.message_id, delegation_id: delegation.id, delegation_version: delegation.version })
      elsif result['create_lead'] && !delegation.allow_crm?
        JrcNico::Notice.publish!(account: delegation.account, user: delegation.user, conversation: conversation,
          event_key: "opportunity:#{conversation.id}", kind: 'opportunity',
          body: "#{conversation.contact.name}: identifiquei interesse comercial. #{result['summary'].to_s.first(1000)}")
      end
      handoff = result['handoff']
      if handoff
        JrcNico::DelegationService.stop(conversation, reason: 'commercial_handoff', status: 'needs_human', summary: result['summary'])
        delegation.reload
        JrcNico::Notice.publish!(account: delegation.account, user: delegation.user, conversation: conversation,
          event_key: "handoff:#{turn.id}", kind: 'handoff', body: "#{conversation.contact.name} precisa de você. #{result['summary'].to_s.first(1500)}")
      end
      continuation = conversation.messages.outgoing.where(sender_type: 'AgentBot', sender_id: delegation.agent_bot_id).exists?
      message = Messages::MessageBuilder.new(delegation.agent_bot, conversation,
        content: JrcNico::CustomerReply.normalize(result['reply'], continuation: continuation), private: false, content_attributes: {
          nico_delegation: { id: delegation.id, version: delegation.version, handoff: handoff }, nico_turn_id: turn.id
        }).perform
      delegation.update!(summary: result['summary'], last_message_id: turn.message_id)
      turn.update!(status: 'queued', outgoing_message_id: message.id)
    end
  end
end
