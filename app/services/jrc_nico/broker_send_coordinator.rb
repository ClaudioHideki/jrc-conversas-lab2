class JrcNico::BrokerSendCoordinator
  CONTROL_FIELDS = %w[contact_id contact_inbox_id inbox_id status assignee_id assignee_agent_bot_id team_id].freeze
  REVISION_FIELDS = %w[ownerRevision attendanceRevision controlRevision destinationRevision credentialRevision].freeze

  def self.fingerprint(snapshot, actor_id, content)
    text_hash = Digest::SHA256.hexdigest(content.encode(Encoding::UTF_8))
    fields = ['jrc-nico-send-v1', snapshot.fetch('organizationId'), snapshot.fetch('accountId'), snapshot.fetch('inboxId'),
              snapshot.fetch('remoteConversationId'), actor_id, text_hash]
    Digest::SHA256.hexdigest(fields.join("\n"))
  end

  def self.prepare(access:, command:, arguments:)
    return if arguments['private'] == true

    conversation = access.conversation(arguments.fetch('conversation_id'))
    binding = JrcNico::BrokerSendBinding.resolve(account_id: access.account.id, inbox_id: conversation.inbox_id)
    return unless binding
    raise Pundit::NotAuthorizedError if command.source_notice_id

    authorize_configuration!(access)
    reject_native_run!(conversation)
    conversation, snapshot = read_snapshot(access, arguments, conversation, binding)
    operation = create_preview(access, command, arguments, conversation, snapshot)
    { reply: "Confirmar significa assumir esta conversa de #{conversation.contact.name} e pausar o bot antes de enviar. " \
             'O atendimento permanecerá humano até uma retomada explícita.', result: { broker_send: operation.receipt } }
  end

  def self.read_snapshot(access, arguments, conversation, binding)
    context = JrcBroker::Context.new(account: access.account, user: access.user)
    snapshot = context.client.conversation_attendance(binding.integration_id, conversation.display_id)
    access.authorize!
    conversation = access.conversation(arguments.fetch('conversation_id'))
    binding = JrcNico::BrokerSendBinding.resolve(account_id: access.account.id, inbox_id: conversation.inbox_id)
    raise ArgumentError, JrcNico::BrokerSendBinding::UNAVAILABLE unless binding

    validate_snapshot!(snapshot, context.integration, conversation, binding)
    [conversation, snapshot]
  end

  def self.create_preview(access, command, arguments, conversation, snapshot)
    JrcNico::BrokerSendOperation.create!(
      command: command, account: access.account, user: access.user, conversation: conversation, inbox: conversation.inbox,
      integration_id: snapshot.fetch('integrationId'), request_id: command.request_id, snapshot: snapshot,
      recipient_snapshot: recipient(conversation), fingerprint: fingerprint(snapshot, access.user.id, arguments.fetch('content'))
    )
  end

  def self.confirm(access:, command:)
    operation = command.broker_send_operation
    access.authorize!
    command.session.with_lock do
      command.with_lock do
        next unless command.status == 'awaiting_confirmation'
        raise ArgumentError, 'A prévia expirou. Prepare o envio novamente.' if command.created_at < 15.minutes.ago

        operation.with_lock do
          raise ArgumentError, 'O envio já saiu da prévia.' unless operation.state == 'PREVIEW'

          validate_local!(operation, access)
          operation.update!(state: 'PAUSING', next_attempt_at: Time.current)
          command.update!(
            status: 'executing', approved_at: Time.current,
            execution_context: command.execution_context.merge('authorization' => { 'source' => 'operator', 'user_id' => access.user.id }),
            result: { broker_send: operation.receipt }, reply: 'Pausa solicitada. A mensagem aguarda a confirmação do Broker.'
          )
        end
      end
    end
    command
  end

  def self.recipient(conversation)
    conversation.reload
    route = conversation.contact_inbox.reload
    unless route.contact_id == conversation.contact_id && route.inbox_id == conversation.inbox_id
      raise ArgumentError, 'O destinatário ou a rota da conversa mudou. Revise uma nova prévia.'
    end

    conversation.attributes.slice(*CONTROL_FIELDS).merge(broker_recipient_identity(conversation)).merge(
      'inbox_identity' => recipient_inbox_identity(conversation),
      'contact_identity' => Digest::SHA256.hexdigest(
        [conversation.contact_id, conversation.contact.reload.phone_number, conversation.contact.email].join("\n")
      ),
      'source_identity' => Digest::SHA256.hexdigest(route.source_id.to_s)
    )
  end

  def self.recipient_inbox_identity(conversation)
    conversation.inbox.reload.attributes.slice('id', 'account_id', 'channel_type', 'channel_id')
  end
  private_class_method :recipient_inbox_identity

  def self.broker_recipient_identity(conversation)
    integration = JrcBrokerIntegration.find_by(account_id: conversation.account_id)
    binding = JrcNico::BrokerSendBinding.resolve(account_id: conversation.account_id, inbox_id: conversation.inbox_id)
    { 'broker_configuration' => integration&.attributes&.slice('id', 'account_id', 'broker_origin', 'organization_id', 'destination_revision'),
      'broker_binding' => binding&.identity }
  end

  def self.authorize_configuration!(access)
    access.authorize!
    return if JrcBroker::Configuration.enabled? && access.account.feature_enabled?('jrc_broker')

    raise ArgumentError, 'A integração Broker desta conta precisa estar configurada.'
  end

  def self.reject_native_run!(conversation)
    return unless JrcFlowRun.live.exists?(account_id: conversation.account_id, conversation_id: conversation.id)

    raise ArgumentError, 'Esta conversa possui um Flow nativo ativo. Transfira pelo executor responsável antes de usar este envio.'
  end

  def self.validate_local!(operation, access, check_recipient: true)
    authorize_configuration!(access)
    conversation = access.conversation(operation.conversation.display_id)
    validate_binding!(operation, access, conversation)
    validate_content!(operation, access, conversation)
    if check_recipient && recipient(conversation) != operation.recipient_snapshot
      raise ArgumentError, 'O destinatário ou o controle da conversa mudou. Revise uma nova prévia.'
    end

    reject_native_run!(conversation) if check_recipient
    conversation
  end

  def self.validate_binding!(operation, access, conversation)
    binding = JrcNico::BrokerSendBinding.resolve(account_id: access.account.id, inbox_id: operation.inbox_id)
    valid = conversation.id == operation.conversation_id && conversation.inbox_id == operation.inbox_id &&
            binding&.integration_id == operation.integration_id && operation.user_id == access.user.id
    raise ArgumentError, 'O destinatário ou o vínculo mudou. Revise uma nova prévia.' unless valid

    binding.validate_snapshot!(operation.snapshot)
  end

  def self.validate_content!(operation, access, conversation)
    arguments = operation.command.arguments
    valid = arguments['private'] != true && arguments['conversation_id'] == conversation.display_id &&
            fingerprint(operation.snapshot, access.user.id, arguments.fetch('content')) == operation.fingerprint
    raise ArgumentError, 'O destinatário ou o conteúdo aprovado mudou. Revise uma nova prévia.' unless valid
  end

  def self.validate_snapshot!(snapshot, integration, conversation, binding)
    scope = { 'organizationId' => integration.organization_id, 'integrationId' => binding.integration_id,
              'accountId' => conversation.account_id, 'inboxId' => conversation.inbox_id, 'remoteConversationId' => conversation.display_id,
              'remoteContactId' => conversation.contact_id }
    valid = snapshot.is_a?(Hash) && scope.all? { |key, value| snapshot[key] == value } && valid_snapshot_fields?(snapshot, integration)
    raise ArgumentError, 'O vínculo confirmado pelo Broker não corresponde a esta conversa.' unless valid

    binding.validate_snapshot!(snapshot)
  end

  def self.valid_snapshot_fields?(snapshot, integration)
    snapshot['destinationRevision'] == integration.destination_revision && %w[BOT HUMAN].include?(snapshot['mode']) &&
      REVISION_FIELDS.all? { |key| snapshot[key].is_a?(Integer) && snapshot[key] >= 0 } &&
      %w[channelId conversationId].all? { |key| JrcBroker::Client::UUID.match?(snapshot[key].to_s) }
  end
end
