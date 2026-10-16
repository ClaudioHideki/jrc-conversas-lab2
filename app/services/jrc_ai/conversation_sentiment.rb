# frozen_string_literal: true

class JrcAi::ConversationSentiment
  MESSAGE_LIMIT = 100
  CHARACTER_LIMIT = 1000

  def self.call(access, conversation_id)
    conversation = access.conversation(conversation_id)
    messages = public_messages(conversation)
    raise ArgumentError, 'Não há mensagens públicas de texto para analisar.' if messages.empty?

    account = access.account
    payload = { account_id: account.id, request_id: SecureRandom.uuid, conversation_id: conversation.display_id,
                channel: conversation.inbox.channel_type, messages: message_rows(messages) }
    result = JrcNico::OperationalInference.metered(account: account, user: access.user, kind: 'sentiment',
                                                   reservation_tokens: payload.to_json.bytesize + 16_000,
                                                   request_id: payload[:request_id]) do |provider, ledger|
      JrcNico::RuntimeClient.new(provider: provider, ledger: ledger).sentiment(payload)
    end
    result_summary(result, access, conversation, messages)
  end

  def self.public_messages(conversation)
    conversation.messages.where(private: false, message_type: [:incoming, :outgoing])
                .where.not(content: [nil, '']).reorder(created_at: :desc, id: :desc).limit(MESSAGE_LIMIT).to_a.reverse
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
      { id: message.id, role: role, content: message.content.to_s.first(CHARACTER_LIMIT) }
    end
  end
  private_class_method :message_rows

  def self.result_summary(result, access, conversation, messages)
    report = result.fetch('report')
    validate_evidence!(report, messages)

    { conversation_id: conversation.display_id, message: report.fetch('summary'),
      sentiment_report: report.merge('analysis_version' => 1, 'inferred' => true, 'source_window' => source_window(messages),
                                     'account_id' => access.account.id, 'conversation_id' => conversation.display_id,
                                     'channel' => conversation.inbox.channel_type, 'analyzed_at' => Time.current.iso8601,
                                     'model' => result.fetch('model'), 'message_count' => messages.size,
                                     'first_message_at' => messages.first.created_at.iso8601,
                                     'last_message_at' => messages.last.created_at.iso8601,
                                     'scope' => 'Últimas 100 mensagens públicas de texto; até 1000 caracteres por mensagem. ' \
                                                'Anexos e áudios não analisados.') }
  end
  private_class_method :result_summary

  def self.validate_evidence!(report, messages)
    evidence = report['evidence']
    ids = messages.map(&:id)
    return if evidence.is_a?(Array) && evidence.all? { |item| item.is_a?(Hash) && ids.include?(item['message_id']) }

    raise JrcNico::RuntimeClient::Error, 'invalid_response'
  end
  private_class_method :validate_evidence!

  def self.source_window(messages)
    { 'message_ids' => messages.map(&:id), 'message_limit' => MESSAGE_LIMIT, 'characters_per_message' => CHARACTER_LIMIT,
      'truncated_message_count' => messages.count { |message| message.content.to_s.length > CHARACTER_LIMIT },
      'first_message_at' => messages.first.created_at.iso8601, 'last_message_at' => messages.last.created_at.iso8601,
      'digest' => Digest::SHA256.hexdigest(message_rows(messages).to_json) }
  end
  private_class_method :source_window
end
