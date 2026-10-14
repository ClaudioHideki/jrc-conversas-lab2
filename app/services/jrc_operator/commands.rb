require 'stringio'
class JrcOperator::Commands
  def initialize(binding:, user:)
    @binding = binding
    @user = user
    @client = JrcOperator::Client.new(binding)
  end

  def remote!(kind, data, key)
    authorize!(kind)
    operation, created = record!(kind, data, key)
    return operation if operation.state == 'confirmed'

    result = if created
               @client.rede(kind.to_sym, data.merge('external_actor' => @user.id.to_s), key: key)
             else
               @client.rede(:operation, { 'key' => key, 'external_actor' => @user.id.to_s })
             end
    operation.update!(state: 'confirmed', result: result)
    operation
  rescue JrcOperator::Error => e
    operation&.update!(state: 'rejected', result: { 'code' => e.message }) if e.status.in?([403, 409])
    raise
  end

  def prepare!(charge_id, key)
    authorize!('prepare_boleto')
    operation, = record!('prepare_boleto', { 'charge_id' => charge_id.to_s }, key)
    operation.with_lock do
      next operation if operation.state == 'confirmed'

      @client.collectible!(charge_id)
      bytes = @client.bemtevi('cobranca/segundaVia', { 'codcobranca' => charge_id.to_i }, pdf: true)
      operation.boleto.attach(io: StringIO.new(bytes), filename: "boleto-#{charge_id}.pdf", content_type: 'application/pdf')
      operation.update!(state: 'confirmed', result: { 'charge_id' => charge_id.to_s, 'observed_at' => Time.current.iso8601 })
    end
    operation
  end

  def send!(prepared_id, conversation_id, content, key)
    authorize!('send_boleto')
    prepared = prepared_boleto!(prepared_id)
    conversation = authorized_conversation!(conversation_id)
    validate_message!(content)

    # Only one delivery per prepared PDF and conversation; a new HTTP key cannot duplicate it.
    prepared.with_lock { schedule_boleto!(prepared, conversation, content, key) }
  end

  private

  def prepared_boleto!(id)
    prepared = @binding.operations.find(id)
    ready = prepared.kind == 'prepare_boleto' && prepared.state == 'confirmed' && prepared.boleto.attached?
    raise JrcOperator::Error, 'BOLETO_NOT_READY' unless ready

    prepared
  end

  def authorized_conversation!(id)
    conversation = @binding.account.conversations.find(id)
    context = { account: @binding.account, user: @user, account_user: @binding.account.account_users.find_by!(user_id: @user.id) }
    matches_binding = conversation.contact_id == @binding.contact_id && @binding.allowed_inbox_ids.include?(conversation.inbox_id)
    raise Pundit::NotAuthorizedError unless matches_binding && ConversationPolicy.new(context, conversation).show?
    raise JrcOperator::Error, 'CHANNEL_WINDOW_CLOSED' unless conversation.can_reply?

    conversation
  end

  def validate_message!(content)
    raise JrcOperator::Error, 'MESSAGE_REQUIRED' unless content.is_a?(String) && content.strip.present? && content.length <= 2000
  end

  def schedule_boleto!(prepared, conversation, content, key)
    existing = @binding.operations.find_by(kind: 'send_boleto', prepared_operation_id: prepared.id, conversation_id: conversation.id)
    return existing if existing&.message_id

    @client.collectible!(prepared.request_data.fetch('charge_id'))
    operation, = record!('send_boleto', { 'prepared_id' => prepared.id, 'conversation_id' => conversation.id, 'content' => content }, key)
    raise JrcOperator::Error, 'BOLETO_ALREADY_SCHEDULED' unless operation.state == 'pending'

    deliver_boleto!(operation, prepared, conversation, content)
  end

  def deliver_boleto!(operation, prepared, conversation, content)
    operation.update!(prepared_operation_id: prepared.id, conversation_id: conversation.id)
    message_params = { content: content, message_type: 'outgoing', private: false, attachments: [prepared.boleto.blob.signed_id] }
    message = Messages::MessageBuilder.new(@user, conversation, message_params).perform
    operation.update!(state: 'confirmed', message: message, result: { 'message_id' => message.id, 'delivery_status' => 'scheduled' })
    operation
  end

  def authorize!(kind)
    @binding = JrcOperator::Access.new(account: @binding.account, user: @user).binding!(@binding.id, kind)
  end

  def record!(kind, data, key)
    operation = JrcOperator::Operation.transaction(requires_new: true) do
      @binding.operations.create!(user: @user, kind: kind, key: key, request_data: data)
    end
    [operation, true]
  rescue ActiveRecord::RecordNotUnique
    operation = @binding.operations.find_by!(key: key)
    unless operation.kind == kind && operation.request_data == data && operation.user_id == @user.id
      raise JrcOperator::Error.new('IDEMPOTENCY_CONFLICT',
                                   409)
    end
    raise JrcOperator::Error.new('OPERATION_REJECTED', 409) if operation.state == 'rejected'

    [operation, false]
  end
end
