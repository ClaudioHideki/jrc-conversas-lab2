# Custody proof never grants human/executor authority. No marker-based adoption,
# content stripping, callback or timestamp mutation is performed here.
class JrcBroker::LiveHistoryCustody
  def initialize(scope)
    @scope = scope
  end

  def native_message(conversation, input, recipient)
    receipt = one_receipt(native_scope(input))
    return unless receipt

    expected = verify_native_receipt!(receipt, conversation, input, recipient)

    message = receipt.message
    verify_message!(message, conversation, input['direction'], [expected, raw_content(input)])
    verify_clock!(message, receipt.envelope, input.fetch('occurred_at'))
    compare_media!(descriptor(input), receipt.envelope['media'])
    verify_media!(message, descriptor(input))
    message
  end

  def historical_message(input)
    receipt = one_receipt(history_scope(input))
    return unless receipt

    source, expected = historical_source!(receipt, input)
    message = receipt.message
    verify_message!(message, receipt.conversation, input['message_type'], [raw_content(source), expected])
    verify_clock!(message, input, source.fetch('occurred_at'))
    compare_media!(descriptor(source), input['media'])
    require_ready!(receipt, input) if descriptor(source)
    verify_media!(message, descriptor(source))
    message
  end

  def verify_reused_attachment!(intent, message)
    receipt = intent.receipt
    context = receipt&.origin_context
    raise ArgumentError, 'JRC_INGRESS_ATTACHMENT' unless context && context['live_receipt_id']

    native = native_scope(context.fetch('request')).find_by(id: context['live_receipt_id'], message_id: message.id, state: 'PERSISTED')
    raise ArgumentError, 'JRC_INGRESS_ATTACHMENT' unless native

    matched = native_message(message.conversation, context.fetch('request'), receipt.recipient)
    raise ArgumentError, 'JRC_INGRESS_ATTACHMENT' unless matched.id == message.id
  end

  private

  def historical_source!(receipt, input)
    context = receipt.origin_context
    exact_history_context!(receipt, context, input)
    source = context.fetch('request')
    expected = JrcBroker::IngressPresentation.content(source, receipt.recipient, input.fetch('message_origin'))
    raise ArgumentError, 'JRC_INGRESS_CONTENT' unless source['direction'] == input['message_type'] && expected == input['content']

    [source, expected]
  end

  def verify_clock!(message, offered, original)
    return unless offered.key?('occurred_at')

    raise ArgumentError, 'JRC_INGRESS_CLOCK' unless offered['occurred_at'] == original && message.created_at.to_i == original
  end

  def one_receipt(relation)
    rows = relation.lock.limit(2).to_a
    raise ArgumentError, 'JRC_INGRESS_AMBIGUOUS' if rows.size > 1

    rows.first
  end

  def descriptor(input)
    input.dig('content', 'type') == 'MEDIA' ? input.fetch('content') : nil
  end

  def require_ready!(receipt, input)
    ready = JrcBrokerHistoryMedia.exists?(receipt_id: receipt.id, message_id: receipt.message_id, instance_id: input['instance_id'],
                                          destination_revision: input['destination_revision'], state: 'READY')
    raise ArgumentError, 'JRC_INGRESS_PENDING' unless ready
  end

  def verify_native_receipt!(receipt, conversation, input, recipient)
    exact_scope!(receipt, input)
    raise ArgumentError, 'JRC_INGRESS_PENDING' unless receipt.state == 'PERSISTED'

    expected = JrcBroker::IngressPresentation.content(input, recipient, receipt.envelope.fetch('message_origin'))
    valid = receipt.conversation_id == conversation.display_id && receipt.envelope['message_type'] == input['direction'] &&
            receipt.envelope['content'] == expected
    raise ArgumentError, 'JRC_INGRESS_CONTENT' unless valid

    expected
  end

  def native_scope(input)
    JrcBrokerLiveReceipt.where(account_id: @scope.account.id, inbox_id: @scope.inbox.id,
                               organization_id: input.fetch('organization_id'), integration_id: input.fetch('integration_id'),
                               broker_message_id: input.fetch('broker_message_id'))
  end

  def history_scope(input)
    JrcBrokerHistoryReceipt.where(account_id: @scope.account.id, inbox_id: @scope.inbox.id, record_kind: 'MESSAGE',
                                  organization_id: input.fetch('organization_id'), integration_id: input.fetch('integration_id'),
                                  source_id: input.fetch('broker_message_id'))
  end

  def exact_scope!(receipt, input)
    valid = receipt.instance_id == @scope.binding.instance_id && receipt.instance_id == input['instance_id'] &&
            receipt.destination_revision == @scope.integration.destination_revision && receipt.destination_revision == input['destination_revision']
    raise ArgumentError, 'JRC_INGRESS_SCOPE' unless valid
  end

  def exact_history_context!(receipt, context, input)
    expected = { 'account_id' => @scope.account.id, 'inbox_id' => @scope.inbox.id, 'message_id' => receipt.message_id,
                 'conversation_id' => input['conversation_id'], 'instance_id' => input['instance_id'],
                 'destination_revision' => input['destination_revision'] }
    raise ArgumentError, 'JRC_INGRESS_LEGACY_UNPROVEN' unless context.is_a?(Hash) && context.slice(*expected.keys) == expected

    source = context.fetch('request')
    valid = source.slice('organization_id', 'integration_id', 'instance_id', 'destination_revision', 'broker_message_id') ==
            input.slice('organization_id', 'integration_id', 'instance_id', 'destination_revision', 'broker_message_id')
    raise ArgumentError, 'JRC_INGRESS_SCOPE' unless valid
  end

  def verify_message!(message, conversation, direction, bodies)
    expected = { 'account_id' => @scope.account.id, 'inbox_id' => @scope.inbox.id, 'conversation_id' => conversation.id,
                 'private' => false, 'message_type' => direction, 'content_type' => 'text' }
    valid = message && message.attributes.slice(*expected.keys) == expected && bodies.include?(message.content)
    raise ArgumentError, 'JRC_INGRESS_MESSAGE' unless valid
  end

  def raw_content(input)
    input.dig('content', input.dig('content', 'type') == 'MEDIA' ? 'caption' : 'text')
  end

  def compare_media!(left, right)
    valid = if left.nil?
              right.nil?
            else
              right.is_a?(Hash) && left.slice('mime_type', 'byte_size',
                                              'sha256') == right.slice('mime_type', 'byte_size', 'sha256')
            end
    raise ArgumentError, 'JRC_INGRESS_MEDIA' unless valid
  end

  def verify_media!(message, descriptor)
    attachments = message.attachments.to_a
    if descriptor.nil?
      raise ArgumentError, 'JRC_INGRESS_MEDIA' unless attachments.empty?

      return
    end
    raise ArgumentError, 'JRC_INGRESS_MEDIA' unless attachments.one? && attachments.first.file.attached?

    blob = attachments.first.file.blob
    valid = blob.byte_size == descriptor.fetch('byte_size') && blob.content_type == descriptor.fetch('mime_type')
    raise ArgumentError, 'JRC_INGRESS_MEDIA' unless valid

    JrcBroker::LiveIngressMedia.new.verify_blob!(blob, descriptor)
  end
end
