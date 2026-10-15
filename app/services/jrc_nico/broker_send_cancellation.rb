class JrcNico::BrokerSendCancellation
  def self.request(access:, command:)
    access.authorize!
    operation = command.broker_send_operation
    raise Pundit::NotAuthorizedError unless operation.account_id == access.account.id && operation.user_id == access.user.id

    command.with_lock do
      operation.with_lock do
        if operation.message_created_at || operation.message_id || %w[MESSAGE_CREATED COMPLETED].include?(operation.state)
          raise ArgumentError, 'A mensagem já foi registrada; o cancelamento não desfaz um envio.'
        end
        next if operation.state == 'CANCELED'

        start!(operation, 'OPERATOR_CANCELLED')
      end
    end
    command
  end

  # Caller holds Command (when present) -> operation locks. A late pause cannot create a Message after cancellation.
  def self.start!(operation, reason)
    preview = operation.state == 'PREVIEW'
    operation.update!(state: preview ? 'CANCELED' : 'CANCELING', last_error: reason,
                      lease_token: nil, lease_expires_at: nil, next_attempt_at: preview ? nil : Time.current)
    operation.update_command!(
      status: preview ? 'cancelled' : 'executing', result: { broker_send: operation.receipt },
      reply: preview ? 'Ação cancelada antes de solicitar a pausa.' : 'Envio cancelado. Aguardando liberação da intenção no Broker.'
    )
  end

  # The worker validates the remote receipt and holds its current lease before calling this method.
  def self.complete!(operation, receipt)
    preserve_human_attendance(operation) if receipt['mode'] == 'HUMAN'
    operation.update!(state: 'CANCELED', takeover_id: receipt.fetch('id'), lease_token: nil, lease_expires_at: nil, next_attempt_at: nil)
    operation.update_command!(status: 'cancelled', result: { broker_send: operation.receipt },
                              reply: 'Envio cancelado e intenção liberada. Nenhuma mensagem foi criada; o atendimento atual foi preservado.')
  end

  def self.preserve_human_attendance(operation)
    operation.conversation.with_lock do
      next unless JrcNico::BrokerSendCoordinator.recipient(operation.conversation) == operation.recipient_snapshot
      next if JrcFlowRun.live.exists?(account_id: operation.account_id, conversation_id: operation.conversation_id)

      operation.conversation.update!(status: 'open', assignee_agent_bot: nil)
    end
  end

  def self.context_lost?(error)
    return [400, 401, 403, 404, 409].include?(error.status) if error.is_a?(JrcBroker::Client::Error)

    [JrcBroker::CredentialStore::InvalidCredential, JrcBroker::Configuration::InvalidConfiguration,
     ActiveRecord::RecordNotFound, ArgumentError].any? { |type| error.is_a?(type) }
  end
end
