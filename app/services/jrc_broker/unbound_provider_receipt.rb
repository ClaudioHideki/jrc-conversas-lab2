# Consumption is restricted to the operator-only projection runner. It reads a
# document derived from independent read-only scans, never a dashboard payload.
class JrcBroker::UnboundProviderReceipt
  KIND = 'DIRECT_EVOLUTION_UNBOUND_V1'.freeze
  ACKS = {'DELIVERY_ACK' => 'DELIVERED', 'READ' => 'READ'}.freeze
  SHA = /\A[0-9a-f]{64}\z/

  def initialize(message, input, digest, peer)
    @message, @input, @digest, @peer = message, input, digest, peer
  end

  def verify!
    @inbox = Inbox.lock.find_by!(id: @message.inbox_id, account_id: @message.account_id, channel_type: 'Channel::Api')
    reject! if JrcBrokerInboxBinding.exists?(account_id: @message.account_id, inbox_id: @inbox.id) ||
               JrcBrokerWebhookObligation.exists?(message_id: @message.id)
    attrs = @message.content_attributes.to_h
    extra = @message.additional_attributes.to_h
    eligible_status = @message.sent? || @message.failed? ||
                      ((@message.delivered? || @message.read?) && Messages::DirectWaidRetryGuard.configured?(@inbox))
    reject! unless @message.sender_type == 'User' && @message.sender_id.present? && eligible_status &&
                   @message.text? && !@message.attachments.exists? && @message.content.is_a?(String) && @message.content.present?
    reject! if [attrs,extra].any? { |data| %w[jrc_broker_outbound jrc_broker_message_id jrc_broker_historical external_echo deleted automation_rule_id
                                              campaign_id jrc_campaign_evolution jrc_campaign_broker].any? { |k| data[k].present? } }
    custody = @input.fetch('custody')
    origin = ENV.fetch('FRONTEND_URL').delete_suffix('/')
    channel = Channel::Api.lock.find_by!(id: @inbox.channel_id, account_id: @message.account_id)
    reject! unless channel.webhook_url.present? && Digest::SHA256.hexdigest(channel.webhook_url) == custody['webhook_url_sha256'] &&
                   custody['account_id'] == @message.account_id && custody['inbox_id'] == @message.inbox_id && custody['origin'] == origin &&
                   custody['kind'] == 'EXCLUSIVE_DIRECT_EVOLUTION' && SHA.match?(custody['snapshot_sha256'].to_s)
    start_at, end_at = %w[valid_from valid_until].map { |field| Time.iso8601(custody.fetch(field)) }
    reject! unless @message.created_at >= start_at && @message.created_at < end_at
    negative = @input.fetch('broker_scan')
    reject! unless negative['tenant_count'] == 1 && negative['account_id'] == @message.account_id && negative['origin'] == origin &&
                   negative['inbox_id'] == @message.inbox_id && negative['message_id'] == @message.id &&
                   negative['connections'] == 0 && negative['jobs'] == 0 && negative['linked_messages'] == 0
    provider = @input.fetch('provider')
    key = provider.fetch('key_id')
    reject! if Message.where(account_id: @message.account_id, inbox_id: @inbox.id, source_id: @message.source_id).where.not(id: @message.id).exists?
    state = ACKS[provider['ack']]
    remote = provider['remote_jid']
    reject! unless remote == @peer || (remote.to_s.match?(/\A\d{1,30}@lid\z/) && provider['remote_jid_alt'] == @peer)
    reject! unless state && @peer.match?(/\A[1-9]\d{7,14}@s\.whatsapp\.net\z/) && provider['peer'] == @peer &&
                   provider['from_me'] == true && provider['origin'] == origin && provider['row_id'].present? && provider['ack_id'].present? &&
                   provider['account_id'] == @message.account_id && provider['inbox_id'] == @inbox.id && provider['message_id'] == @message.id &&
                   provider['conversation_id'] == @message.conversation.display_id && provider['part_count'] == 1 &&
                   provider['instance_id'].present? && provider['instance_id'] == custody['physical_instance_id'] &&
                   custody['generation'].is_a?(String) && custody['generation'].present? && provider['body_sha256'] == Digest::SHA256.hexdigest(@message.content) &&
                   key.is_a?(String) && key.size.between?(1,512) && !key.match?(JrcBroker::OutboundReceipt::INVALID_PROVIDER_ID) &&
                   @message.source_id == "WAID:#{key}" && SHA.match?(provider['record_sha256'].to_s)
    occurred = Time.at(provider.fetch('message_timestamp')).utc
    reject! unless occurred >= start_at && occurred < end_at
    {'kind' => KIND, 'state' => state, 'provider_key_sha256' => Digest::SHA256.hexdigest(key), 'peer_sha256' => Digest::SHA256.hexdigest(@peer),
     'physical_instance_id' => provider.fetch('instance_id'), 'generation' => custody.fetch('generation'), 'evidence_sha256' => @digest,
     'provider_record_sha256' => provider.fetch('record_sha256'), 'custody_sha256' => custody.fetch('snapshot_sha256'),
     'conversation_id' => @message.conversation_id, 'inbox_id' => @message.inbox_id}
  end

  private

  def reject!
    raise ArgumentError, 'JRC_DIRECT_RECEIPT_NOT_PROVEN'
  end
end
