class JrcNico::ContextBuilder
  def initialize(account:, user:, conversation:)
    @access = JrcNico::Access.new(account: account, user: user, conversation: conversation)
  end

  def build(message, agent_key: 'nico')
    @access.authorize!
    {
      conversation: @access.conversation.messages.where(account_id: @access.account.id, private: false).where.not(content: [nil, ''])
                           .reorder(id: :desc).limit(40).to_a.reverse.map do |entry|
        { source: 'conversation', reference: "message:#{entry.id}", text: "#{entry.message_type}: #{entry.content.to_s.first(1000)}" }
      end,
      crm: crm_context,
      knowledge: knowledge_context(message),
      erp: JrcNico::ErpContext.build(account: @access.account, user: @access.user, conversation: @access.conversation, agent_key: agent_key)
    }
  end

  private

  def crm_context
    leads = @access.leads.order(updated_at: :desc).limit(5).map do |lead|
      { source: 'crm', reference: "lead:#{lead.id}", text: [lead.name, lead.company_name, lead.status, lead.notes].compact.join(' | ').first(1000) }
    end
    deals = @access.deals.order(updated_at: :desc).limit(5).map do |deal|
      { source: 'crm', reference: "deal:#{deal.id}", text: [deal.title, deal.status, deal.description].compact.join(' | ').first(1000) }
    end
    leads + deals
  end

  def knowledge_context(message)
    JrcNico::KnowledgeDocument.where(account_id: @access.account.id).approved
                             .where("to_tsvector('portuguese', title || ' ' || body) @@ plainto_tsquery('portuguese', ?)", message)
                             .order(updated_at: :desc).limit(10).map do |document|
      { source: 'knowledge', reference: "document:#{document.id}:#{document.digest.first(12)}", text: "#{document.title}\n#{document.body}".first(2000) }
    end
  end
end
