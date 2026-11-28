# Operator-only reader of independently collected Broker and provider rows. A
# trusted shell pins the evidence file's digest before constructing this class.
# No message, attachment or delivery mutation is performed by the public API.
class JrcBroker::ProjectionReceipt
  POINTER = 'jrc_delivery_projection_audit_id'.freeze
  DISPLAY = 'jrc_delivery_projection'.freeze
  ACTION = 'jrc_channel_receipt'.freeze
  MEDIA_ERRORS = %w[MEDIA_DOWNLOAD_FAILED MEDIA_NOT_FOUND].freeze
  RANK = JrcBroker::OutboundReceipt::RANK

  def self.current(message, attrs)
    audit_id = attrs[POINTER]
    return unless audit_id.is_a?(Integer) && audit_id.positive?

    audit = Audited::Audit.find_by(id: audit_id, auditable_type: 'Message', auditable_id: message.id,
                                  associated_type: 'Account', associated_id: message.account_id, action: ACTION)
    receipt = audit&.audited_changes
    return unless receipt && receipt['inbox_id'] == message.inbox_id && receipt['conversation_id'] == message.conversation_id

    receipt
  end

  def initialize(input, evidence_digest)
    @input = input
    @digest = evidence_digest
  end

  def perform(apply: false)
    Message.transaction do
      @message = Message.lock.find_by!(id: @input.fetch('message_id'), account_id: @input.fetch('account_id'), inbox_id: @input.fetch('inbox_id'))
      @attrs = @message.content_attributes.to_h
      check!(@digest.match?(/\A[0-9a-f]{64}\z/) && @message.outgoing? && !@message.private?, 'message_scope')
      check!(@message.conversation_id == @input.fetch('rails_conversation_id') && @message.conversation.display_id == @input.fetch('remote_conversation_id'), 'conversation')
      check!(@message.inbox.channel_type == 'Channel::Api' && @message.conversation.inbox_id == @message.inbox_id, 'inbox')
      validate_scope!
      validate_peer!
      receipt = @input.fetch('kind') == 'DIRECT_EVOLUTION_RECEIPT_V1' ? direct_receipt! : mirror_receipt!
      prior = self.class.current(@message, @attrs)
      check!(!@attrs.key?(POINTER) || prior, 'prior_audit')
      if prior
        identity = %w[kind canonical_message_id provider_key_sha256 peer_sha256 channel_id job_id]
        check!(prior.slice(*identity) == receipt.slice(*identity), 'receipt_identity')
        return :already_confirmed if RANK.fetch(prior.fetch('state')) >= RANK.fetch(receipt.fetch('state'))
      end
      check!(@message.updated_at.utc.iso8601(6) == @input.fetch('expected_updated_at'), 'stale_snapshot')
      return :eligible unless apply

      audit = Audited::Audit.create!(auditable: @message, associated: @message.account, action: ACTION, audited_changes: receipt)
      written = @message.update_columns(content_attributes: @attrs.merge(POINTER => audit.id)) # rubocop:disable Rails/SkipsModelValidations
      check!(written, 'stale_snapshot')
      :recorded
    end
  end

  private

  def validate_scope!
    binding = JrcBrokerInboxBinding.lock('FOR SHARE').find_by!(account_id: @message.account_id, inbox_id: @message.inbox_id)
    integration = JrcBrokerIntegration.lock('FOR SHARE').find_by!(account_id: @message.account_id)
    check!(binding.integration_id == @input.fetch('integration_id') && binding.instance_id == @input.fetch('instance_id') &&
           integration.organization_id == @input.fetch('organization_id') && integration.destination_revision == @input.fetch('destination_revision'), 'binding')
    @obligation = JrcBrokerWebhookObligation.lock('FOR SHARE').find_by!(account_id: @message.account_id, inbox_id: @message.inbox_id, message_id: @message.id)
    check!(@obligation.state == 'delivered' && @obligation.current_binding? && @obligation.delivery_id == @input.fetch('delivery_id'), 'obligation')
  end

  def validate_peer!
    @peer = @input.fetch('peer')
    contact = @message.conversation.contact
    route = @message.conversation.contact_inbox
    check!(route && route.id == @input.fetch('contact_inbox_id') && route.inbox_id == @message.inbox_id &&
           route.contact_id == contact.id && contact.id == @input.fetch('contact_id') && contact.account_id == @message.account_id, 'peer_route')
    check!(Digest::SHA256.hexdigest(route.source_id.to_s) == @input.fetch('route_source_sha256'), 'source')
    known_jid = contact.additional_attributes.to_h['jrc_broker_jid']
    physical_phone = contact.phone_number.to_s
    matches_phone = physical_phone.match?(/\A\+[1-9]\d{7,14}\z/) && @peer == "#{physical_phone.delete_prefix('+')}@s.whatsapp.net"
    matches_jid = known_jid.present? && known_jid == @peer &&
                  (JrcBroker::HistorySyncBootstrap::INDIVIDUAL.match?(@peer) || JrcBroker::HistorySyncBootstrap::GROUP.match?(@peer))
    check!((matches_jid || matches_phone) && (known_jid.blank? || matches_jid) &&
           (!@peer.end_with?('@s.whatsapp.net') || physical_phone.blank? || matches_phone), 'peer_identity')
  end

  def mirror_receipt!
    check!(@input.fetch('kind') == 'BROKER_MIRROR_RECEIPT_V1', 'kind')
    check!(@message.failed? && MEDIA_ERRORS.include?(@message.external_error) && @input.fetch('media_error') == @message.external_error &&
           @message.attachments.exists?, 'mirror_media')
    canonical = @input.fetch('canonical')
    mapping = @input.fetch('mapping')
    provider = @input.fetch('provider')
    scope = @input.slice('organization_id', 'channel_id')
    marker = @attrs['jrc_broker_message_id']
    check!(JrcBroker::Client::UUID.match?(marker.to_s) && canonical['id'] == marker &&
           @obligation.payload.dig('content_attributes', 'jrc_broker_message_id') == marker, 'mirror_identity')
    check!(mapping == @input.slice('organization_id', 'integration_id', 'channel_id', 'remote_conversation_id', 'message_id').merge(
      'canonical_message_id' => marker, 'broker_conversation_id' => canonical.fetch('conversation_id'), 'peer' => @peer
    ), 'broker_mapping')
    check!(canonical.slice(*scope.keys) == scope && canonical['direction'] == 'OUTGOING' && RANK.key?(canonical['state']) &&
           %w[EXTERNAL_OBSERVED OPERATOR AUTOMATION].include?(canonical['source']) &&
           JrcBroker::Client::UUID.match?(canonical.fetch('conversation_id')) && JrcBroker::Client::UUID.match?(scope.fetch('channel_id')), 'canonical')
    key = canonical.fetch('provider_message_id')
    check!(key.is_a?(String) && key.size.between?(1,512) && !key.match?(JrcBroker::OutboundReceipt::INVALID_PROVIDER_ID), 'provider_key')
    check!(provider.slice(*scope.keys) == scope && provider['peer'] == @peer && provider['from_me'] == true &&
           provider['instance_id'] == @input.fetch('instance_id') &&
           provider['record_sha256'].to_s.match?(/\A[0-9a-f]{64}\z/) &&
           provider['provider_message_id'] == key && provider['state'] == canonical['state'], 'provider')
    check!(@attrs['jrc_broker_outbound'].to_h['canonical_message_id'].in?([nil, marker]) &&
           @attrs['jrc_broker_outbound'].to_h['provider_message_id'].in?([nil, key]), 'conflicting_prior')
    {'kind' => @input.fetch('kind'), 'state' => canonical.fetch('state'), 'canonical_message_id' => marker,
     'channel_id' => scope.fetch('channel_id'), 'provider_key_sha256' => Digest::SHA256.hexdigest(key),
     'peer_sha256' => Digest::SHA256.hexdigest(@peer), 'evidence_sha256' => @digest, 'provider_record_sha256' => provider.fetch('record_sha256'),
     'conversation_id' => @message.conversation_id, 'inbox_id' => @message.inbox_id, 'media_error' => @message.external_error}
  end

  def direct_receipt!
    job = @input.fetch('job')
    check!(job['status'] == 'SUCCEEDED' && job['kind'] == 'CHATWOOT_REPLY' &&
           job['organizationId'] == @input.fetch('organization_id') && job['integrationId'] == @input.fetch('integration_id'), 'job')
    receipt = job.dig('payload', 'directEvolutionReceipt')
    keys = %w[protocol organizationId integrationId channelId jobId origin accountId inboxId conversationId messageId
              destinationRevision credentialRevision obligationId intentId instanceId generation peer sourceId providerMessageId state evidenceSha256]
    check!(receipt.is_a?(Hash) && receipt.keys.sort == keys.sort, 'direct_shape')
    expected = {'protocol' => 'DIRECT_EVOLUTION_RECEIPT_V1', 'organizationId' => job['organizationId'], 'integrationId' => job['integrationId'],
                'origin' => ENV.fetch('FRONTEND_URL').delete_suffix('/'),
                'jobId' => job.fetch('id'), 'channelId' => @input.fetch('channel_id'), 'accountId' => @message.account_id,
                'inboxId' => @message.inbox_id, 'conversationId' => @input.fetch('remote_conversation_id'), 'messageId' => @message.id,
                'destinationRevision' => @input.fetch('destination_revision'), 'obligationId' => @obligation.delivery_id,
                'peer' => @peer, 'sourceId' => @message.source_id}
    check!(receipt.slice(*expected.keys) == expected, 'direct_identity')
    check!([job['id'], receipt['channelId']].all? { |id| JrcBroker::Client::UUID.match?(id.to_s) } &&
           receipt['credentialRevision'].is_a?(Integer) && receipt['credentialRevision'].positive? &&
           [receipt['instanceId'], receipt['generation']].all? { |s| s.is_a?(String) && s.present? } &&
           receipt['evidenceSha256'].to_s.match?(/\A[0-9a-f]{64}\z/), 'direct_chain')
    key = receipt['providerMessageId']
    check!(@peer.match?(/\A[1-9]\d{7,14}@s\.whatsapp\.net\z/) && %w[DELIVERED READ].include?(receipt['state']) && key.is_a?(String) && key.size.between?(1,512) &&
           !key.match?(JrcBroker::OutboundReceipt::INVALID_PROVIDER_ID) && @message.source_id == "WAID:#{key}", 'direct_provider')
    check!(@message.sender_type == 'User' && @message.sender_id.present? && @message.text? && !@message.attachments.exists? &&
           @message.sent? && @message.additional_attributes.to_h.slice('campaign_id', 'jrc_campaign_broker','jrc_campaign_evolution').values.none?(&:present?) &&
           @attrs.slice('automation_rule_id','jrc_broker_message_id','external_echo','jrc_broker_historical','deleted').values.none?(&:present?), 'direct_origin')
    marker = @attrs['jrc_broker_outbound']
    check!(marker.blank? ? receipt['intentId'].nil? : marker.is_a?(Hash) && marker['version'] == 1 && marker['state'] == 'PENDING' &&
           marker['canonical_message_id'].blank? && marker['provider_message_id'].blank? && marker['intent_id'] == @obligation.delivery_id &&
           marker['integration_id'] == @input['integration_id'] && marker['inbox_id'] == @message.inbox_id && receipt['intentId'] == marker['intent_id'], 'direct_intent')
    {'kind' => receipt.fetch('protocol'), 'state' => receipt.fetch('state'), 'job_id' => job.fetch('id'),
     'channel_id' => receipt.fetch('channelId'), 'provider_key_sha256' => Digest::SHA256.hexdigest(key),
     'peer_sha256' => Digest::SHA256.hexdigest(@peer), 'evidence_sha256' => @digest, 'manifest_sha256' => receipt['evidenceSha256'],
     'conversation_id' => @message.conversation_id, 'inbox_id' => @message.inbox_id}
  end

  def check!(condition, code)
    raise ArgumentError, "JRC_RECEIPT_#{code.upcase}" unless condition
  end
end
