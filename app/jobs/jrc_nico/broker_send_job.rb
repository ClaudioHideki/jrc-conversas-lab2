class JrcNico::BrokerSendJob < ApplicationJob
  queue_as :default

  def perform(operation_id)
    operation = JrcNico::BrokerSendOperation.find_by(id: operation_id)
    return unless operation

    token = operation.claim
    return unless token

    dispatch(operation, token)
  rescue StandardError => e
    handle_failure(operation, token, e)
  end

  private

  def dispatch(operation, token)
    if operation.message_created_at && !operation.canonical_message?
      reason = operation.message_id ? 'MESSAGE_RECEIPT_UNVERIFIABLE' : 'MESSAGE_RECEIPT_MISSING'
      pending(operation, token, 'HALTED', reason)
      return
    end
    if operation.state != 'CANCELING' && operation.orphaned_intent?
      abort_send(operation, token, 'ORIGINAL_OPERATOR_REMOVED')
      return
    end

    context = JrcBroker::Context.new(account: operation.account, user: operation.user, actor_id: operation.actor_id)
    validate_context!(operation, context)
    return cancel_remote(operation, token, context.client) if operation.state == 'CANCELING'

    perform_send(operation, token, context)
  end

  def perform_send(operation, token, context)
    access = JrcNico::OperationalAccess.new(account: operation.account, user: operation.user)
    JrcNico::BrokerSendCoordinator.validate_local!(operation, access) unless operation.message_created_at
    return unless operation.message_id || pause_and_create(operation, access, token, context)
    return unless operation.reload.message_id && operation.lease_token == token

    complete_remote(operation, token, context.client)
  end

  def complete_remote(operation, token, client)
    receipt = client.complete_conversation_takeover(operation.integration_id, operation.conversation.display_id,
                                                    operation.takeover_id, message_id: operation.message_id)
    validate_receipt!(operation, receipt)
    raise ArgumentError, 'Recibo de conclusão inconsistente.' unless receipt['state'] == 'COMPLETED'

    complete(operation, token)
  end

  def handle_failure(operation, token, error)
    raise error unless operation && token

    if operation.reload.state == 'CANCELING'
      if JrcNico::BrokerSendCancellation.context_lost?(error)
        pending(operation, token, 'HALTED', 'CANCELLATION_CONTEXT_CHANGED')
      else
        pending(operation, token, 'CANCELING', 'BROKER_UNAVAILABLE')
      end
      return
    end

    dispatch_failure(operation, token, error)
  end

  def dispatch_failure(operation, token, error)
    case error
    when JrcBroker::Client::Error
      client_failed(operation, token, error)
    when JrcBroker::CredentialStore::InvalidCredential, JrcBroker::Configuration::InvalidConfiguration
      pending(operation, token, operation.message_created_at ? 'MESSAGE_CREATED' : 'UNKNOWN', 'BROKER_UNAVAILABLE')
    when ActiveRecord::LockWaitTimeout
      pending(operation, token, operation.reconciliation_state, 'LOCAL_AUTHORITY_BUSY')
    when Pundit::NotAuthorizedError, ArgumentError, ActiveRecord::RecordNotFound, ActiveRecord::RecordInvalid
      abort_send(operation, token, 'ATTENDANCE_AUTHORITY_CHANGED')
    else
      raise error
    end
  end

  def client_failed(operation, token, error)
    if operation.message_created_at
      pending(operation, token, 'MESSAGE_CREATED', 'BROKER_UNAVAILABLE')
    elsif [400, 403, 404, 409].include?(error.status)
      abort_send(operation, token, 'BROKER_REFUSED')
    else
      pending(operation, token, 'UNKNOWN', 'BROKER_UNAVAILABLE')
    end
  end

  def pause_and_create(operation, access, token, context)
    receipt = read_pause(operation, context.client)
    validate_receipt!(operation, receipt)
    operation.with_claim(token) { operation.update!(takeover_id: receipt.fetch('id')) }
    unless receipt['state'] == 'PAUSED'
      receipt['state'] == 'DRAINING' ? pending(operation, token, 'DRAINING') : abort_send(operation, token, 'ATTENDANCE_AUTHORITY_CHANGED')
      return false
    end

    create_message(operation, access, token, receipt.fetch('id'), context.integration)
    true
  end

  def read_pause(operation, client)
    if operation.takeover_id
      client.conversation_takeover(operation.integration_id, operation.conversation.display_id, operation.takeover_id)
    else
      client.start_conversation_takeover(operation.integration_id, operation.conversation.display_id,
                                         takeover_request(operation), key: operation.request_id)
    end
  end

  def takeover_request(operation)
    values = operation.snapshot
    { requestId: operation.request_id, fingerprint: operation.fingerprint,
      expectedOwnerRevision: values.fetch('ownerRevision'), expectedAttendanceRevision: values.fetch('attendanceRevision'),
      expectedControlRevision: values.fetch('controlRevision'), expectedDestinationRevision: values.fetch('destinationRevision'),
      expectedCredentialRevision: values.fetch('credentialRevision') }
  end

  def validate_context!(operation, context)
    expected = operation.snapshot
    integration = context.integration
    return if integration.organization_id == expected['organizationId'] && integration.destination_revision == expected['destinationRevision'] &&
              integration.account_id == operation.account_id

    raise ArgumentError, 'O vínculo da central mudou.'
  end

  def validate_receipt!(operation, receipt)
    fields = %w[organizationId integrationId channelId conversationId accountId inboxId remoteConversationId remoteContactId]
    valid = receipt.is_a?(Hash) && fields.all? { |key| receipt[key] == operation.snapshot[key] } && valid_receipt_fields?(operation, receipt)
    raise ArgumentError, 'Recibo do Broker não corresponde à confirmação.' unless valid
  end

  def valid_receipt_fields?(operation, receipt)
    values = [receipt['requestId'] == operation.request_id, receipt['fingerprint'] == operation.fingerprint,
              JrcBroker::Client::UUID.match?(receipt['id'].to_s), %w[DRAINING PAUSED STALE COMPLETED CANCELED].include?(receipt['state']),
              operation.takeover_id.nil? || receipt['id'] == operation.takeover_id]
    values.all?
  end

  def create_message(operation, access, token, takeover_id, integration)
    operation.with_claim(token) do
      next if operation.message_created_at

      conversation = JrcNico::BrokerSendCoordinator.validate_local!(operation, access)
      conversation.with_lock do
        JrcNico::BrokerSendCommitGate.call(operation: operation, conversation: conversation, integration: integration) do
          message = build_message(operation, conversation, takeover_id)
          operation.update!(takeover_id: takeover_id, message: message, message_created_at: message.created_at, state: 'MESSAGE_CREATED')
          operation.update_command!(result: { broker_send: operation.receipt },
                                    reply: 'Mensagem registrada para envio pelo canal. Atendimento humano mantido.')
        end
      end
    end
  end

  def build_message(operation, conversation, takeover_id)
    Conversations::AssignmentService.new(conversation: conversation, assignee_id: operation.user_id).perform
    conversation.update!(status: 'open')
    metadata = { takeoverId: takeover_id, requestId: operation.request_id, fingerprint: operation.fingerprint }
    Messages::MessageBuilder.new(operation.user, conversation, content: operation.command.arguments.fetch('content'),
                                                               private: false, content_attributes: { jrc_nico_takeover: metadata }).perform
  end

  def abort_send(operation, token, reason)
    return pending(operation, token, 'MESSAGE_CREATED', reason) if operation.message_created_at

    operation.with_claim(token) { JrcNico::BrokerSendCancellation.start!(operation, reason) }
  end

  def cancel_remote(operation, token, client)
    receipt = client.cancel_conversation_takeover(operation.integration_id, operation.conversation.display_id,
                                                  request_id: operation.request_id, fingerprint: operation.fingerprint)
    validate_receipt!(operation, receipt)
    unless receipt['state'] == 'CANCELED' && %w[BOT HUMAN].include?(receipt['mode'])
      pending(operation, token, 'HALTED', 'CANCELLATION_RECEIPT_CONFLICT')
      return
    end

    operation.with_claim(token) { JrcNico::BrokerSendCancellation.complete!(operation, receipt) }
  end

  def complete(operation, token)
    operation.with_claim(token) do
      operation.update!(state: 'COMPLETED', last_error: nil, lease_token: nil, lease_expires_at: nil, next_attempt_at: nil)
      operation.update_command!(status: 'succeeded', result: { broker_send: operation.receipt },
                                reply: 'Mensagem registrada para envio pelo canal. O bot permanece pausado nesta conversa.')
    end
  end

  def pending(operation, token, state, error = nil)
    operation.with_claim(token) do
      operation.update!(state: state, last_error: error, lease_token: nil, lease_expires_at: nil,
                        next_attempt_at: state == 'HALTED' ? nil : 15.seconds.from_now)
      reply = if state == 'HALTED'
                'Não foi possível reconciliar o atendimento. Confira a conversa e o registro da mensagem antes de tentar outra ação.'
              elsif state == 'CANCELING'
                'Envio cancelado. Aguardando liberação da intenção no Broker; nenhuma nova mensagem será criada.'
              else
                'A operação aguarda confirmação ou reconciliação. Nenhuma mensagem será repetida.'
              end
      operation.update_command!(status: state == 'HALTED' ? 'unknown' : 'executing', result: { broker_send: operation.receipt }, reply: reply)
    end
  end
end
