# frozen_string_literal: true

# Corrects only the missing public conversation identifier in a terminal
# obligation. This service has no transition to pending and no transport client.
class JrcBroker::TerminalConversationRepair
  ACTION = 'jrc_terminal_conversation_repair'
  EXCLUDED = %w[jrc_broker_message_id jrc_broker_historical external_echo deleted automation_rule_id campaign_id
                jrc_campaign_broker jrc_campaign_evolution jrc_campaign_test_delivery_id].freeze

  def initialize(account_id:, inbox_id:, message_id:, delivery_id:)
    @scope = { account_id: account_id, inbox_id: inbox_id }
    @message_id = message_id
    @delivery_id = delivery_id
  end

  def perform(expected_sha256: nil)
    JrcBrokerWebhookObligation.transaction do
      message = Message.lock.find_by!(@scope.merge(id: @message_id))
      row = JrcBrokerWebhookObligation.lock.find_by!(@scope.merge(message_id: message.id, delivery_id: @delivery_id))
      check!(row.state == 'failed' && row.last_error_code == 'JRC_BROKER_DELIVERY_REJECTED' && row.attempts == 1 &&
             row.lease_token.nil? && row.lease_until.nil?, 'terminal')
      payload = row.payload
      conversation = Conversation.lock.find_by!(@scope.merge(id: message.conversation_id))
      Contact.lock.find_by!(id: conversation.contact_id, account_id: row.account_id)
      route = ContactInbox.lock.find_by!(id: conversation.contact_inbox_id, inbox_id: row.inbox_id, contact_id: conversation.contact_id)
      binding = JrcBrokerInboxBinding.lock.find_by!(@scope.merge(id: row.binding_id, integration_id: row.integration_id, instance_id: row.instance_id))
      inbox = Inbox.lock.find_by!(id: row.inbox_id, account_id: row.account_id, channel_type: 'Channel::Api')
      channel = Channel::Api.lock.find_by!(account_id: row.account_id, id: inbox.channel_id)
      check!(row.url.present? && channel.webhook_url == row.url, 'binding')
      verify_original!(message, payload, row, route, conversation)
      field = payload.fetch('conversation').fetch('id')
      prior = Audited::Audit.find_by(auditable: row, associated: row.account, action: ACTION)
      if prior
        proof = prior.audited_changes
        check!(field == conversation.display_id && proof['corrected_payload_sha256'] == digest(payload) &&
               (!expected_sha256 || expected_sha256 == proof['review_sha256']), 'prior_audit')
        next({ result: 'already_corrected', sha256: proof.fetch('review_sha256') })
      end
      check!(field.nil?, 'original_conversation')
      fingerprint = digest([row.delivery_id, message.id, message.account_id, message.inbox_id, row.attempts,
                            message.sender_id, conversation.id, conversation.display_id, route.id, route.source_id,
                            binding.id, binding.integration_id, binding.instance_id, row.url, payload])
      next({ result: 'eligible', sha256: fingerprint }) if expected_sha256.nil?

      check!(fingerprint == expected_sha256, 'stale_review')
      corrected = payload.deep_merge('conversation' => { 'id' => conversation.display_id })
      Audited::Audit.create!(auditable: row, associated: row.account, action: ACTION, audited_changes: {
        'review_sha256' => fingerprint, 'original_payload_sha256' => digest(payload), 'corrected_payload_sha256' => digest(corrected),
        'delivery_id' => row.delivery_id, 'message_id' => message.id, 'conversation_id' => conversation.id, 'display_id' => conversation.display_id
      })
      row.update!(payload: corrected)
      { result: 'corrected_terminal', sha256: fingerprint }
    end
  end

  private

  def verify_original!(message, payload, row, route, conversation)
    check!(message.outgoing? && !message.private? && message.failed? && message.sender_type == 'User' && message.sender_id.present? &&
           message.text? && message.source_id.blank? && !message.attachments.exists?, 'human_original')
    check!(payload['event'] == 'message_created' && payload['message_type'] == 'outgoing' && payload['private'] == false &&
           payload['id'] == message.id && payload.dig('sender', 'type') == 'user' && payload.dig('sender', 'id') == message.sender_id &&
           payload.dig('account', 'id') == row.account_id && payload.dig('inbox', 'id') == row.inbox_id &&
           payload['source_id'].blank? && payload['attachments'].blank?, 'original_identity')
    attributes = [message.content_attributes, message.additional_attributes, payload['content_attributes'], payload['additional_attributes']]
    check!(attributes.all? { |attrs| attrs.is_a?(Hash) && EXCLUDED.none? { |key| attrs[key].present? } }, 'origin')
    stored = payload.dig('content_attributes', 'jrc_broker_outbound')
    current = message.content_attributes['jrc_broker_outbound']
    expected = { 'version' => 1, 'intent_id' => row.delivery_id, 'inbox_id' => row.inbox_id, 'integration_id' => row.integration_id }
    check!((stored.nil? && current.nil?) || [stored, current].all? { |intent| intent.is_a?(Hash) && intent.slice(*expected.keys) == expected &&
           intent['state'] == 'PENDING' && intent['canonical_message_id'].blank? && intent['provider_message_id'].blank? }, 'intent')
    check!(conversation.display_id.to_i.positive? && payload.dig('conversation', 'account', 'id') == row.account_id &&
           payload.dig('conversation', 'inbox_id') == row.inbox_id && route.source_id.present? &&
           payload.dig('conversation', 'contact_inbox', 'id') == route.id && payload.dig('conversation', 'contact_inbox', 'source_id') == route.source_id &&
           payload.dig('conversation', 'meta', 'sender', 'id') == conversation.contact_id, 'route')
    check!(message.content.is_a?(String) && message.content.present? && payload['content'].is_a?(String) && payload['content'].b == message.content.b, 'bytes')
  end

  def digest(value)
    Digest::SHA256.hexdigest(JSON.generate(value))
  end

  def check!(condition, reason)
    raise ArgumentError, "JRC_TERMINAL_CONVERSATION_#{reason}" unless condition
  end
end
