# frozen_string_literal: true

class JrcAi::ConversationSentiment
  def self.call(access, conversation_id)
    conversation = access.conversation(conversation_id)
    messages = public_messages(conversation)
    raise ArgumentError, 'Não há mensagens públicas de texto para analisar.' if messages.empty?

    account = access.account
    payload = { account_id: account.id, request_id: SecureRandom.uuid, conversation_id: conversation.display_id,
                channel: conversation.inbox.channel_type, messages: message_rows(messages) }
    result = JrcNico::OperationalInference.metered(account: account, user: access.user, kind: 'sentiment',
                                                   reservation_tokens: payload.to_json.bytesize + 16_000) do |provider|
      JrcNico::RuntimeClient.new(provider: provider).sentiment(payload)
    end
    result_summary(result, access, conversation, messages)
  end

  def self.public_messages(conversation)
    conversation.messages.where(private: false, message_type: [:incoming, :outgoing])
                .where.not(content: [nil, '']).reorder(created_at: :desc, id: :desc).limit(100).to_a.reverse
  end
  private_class_method :public_messages

  def self.message_rows(messages)
    messages.map do |message|
      role = if message.incoming?
               'customer'
             elsif message.sender_type == 'AgentBot' || message.content_attributes['jrc_flow_run_id'].present? ||
                   message.content_attributes['nico_delegation'].present?
               'bot'
             elsif message.sender_type == 'User'
               'operator'
             else
               'unknown'
             end
      { id: message.id, role: role, content: message.content.to_s.first(1000) }
    end
  end
  private_class_method :message_rows

  def self.result_summary(result, access, conversation, messages)
    { conversation_id: conversation.display_id, message: result.fetch('report').fetch('summary'),
      sentiment_report: result.fetch('report').merge('account_id' => access.account.id, 'conversation_id' => conversation.display_id,
                                                     'channel' => conversation.inbox.channel_type, 'analyzed_at' => Time.current.iso8601,
                                                     'model' => result.fetch('model'), 'message_count' => messages.size,
                                                     'first_message_at' => messages.first.created_at.iso8601,
                                                     'last_message_at' => messages.last.created_at.iso8601,
                                                     'scope' => 'Últimas 100 mensagens públicas de texto; até 1000 caracteres por mensagem. ' \
                                                                'Anexos e áudios não analisados.') }
  end
  private_class_method :result_summary
end
