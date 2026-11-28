# Provider evidence from the authenticated Broker callback, separate from its queue ACK.
class JrcBroker::OutboundReceipt
  class Error < ArgumentError; end

  KEY = 'jrc_broker_outbound'.freeze
  KEYS = %w[version canonical_message_id provider_message_id state].freeze
  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
  RANK = { 'SENT' => 1, 'DELIVERED' => 2, 'READ' => 3 }.freeze
  # Match the Broker's JavaScript whitespace/C0/DEL contract, including Unicode whitespace.
  INVALID_PROVIDER_ID = /[\s\x00-\x1f\x7f\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]/

  def initialize(message, status:, proof:, external_error: nil)
    @message = message
    @status = status
    @proof = proof
    @external_error = external_error
  end

  def perform
    validate_proof!
    @message.with_lock do
      validate_context!
      projection = JrcBroker::ProjectionReceipt.current(@message, @message.content_attributes.to_h)
      if projection
        raise Error, 'broker_delivery_identity_changed' unless projection['kind'] == 'BROKER_MIRROR_RECEIPT_V1' &&
                                                               projection['canonical_message_id'] == @proof['canonical_message_id'] &&
                                                               projection['provider_key_sha256'] == Digest::SHA256.hexdigest(@proof['provider_message_id'].to_s)
        next false if RANK.fetch(@proof['state'], 0) < RANK.fetch(projection['state'])
      end
      prior = @message.content_attributes.to_h[KEY].to_h
      validate_identity!(prior)
      next false if stale?(prior)

      attributes = @message.content_attributes.to_h.merge(KEY => prior.merge(@proof),
                                                          'external_error' => @status == 'failed' ? @external_error : nil)
      # The media failure describes the mirror attachment. A transport ACK must
      # not remove that diagnostic or trigger a message_updated webhook.
      if @message.failed? && JrcBroker::ProjectionReceipt::MEDIA_ERRORS.include?(@message.external_error) &&
         @message.content_attributes['jrc_broker_message_id'].present? && @message.attachments.exists? && RANK.key?(@proof['state'])
        raise Error, 'broker_delivery_identity_changed' unless @message.content_attributes['jrc_broker_message_id'] == @proof['canonical_message_id']

        next @message.update_columns(content_attributes: @message.content_attributes.to_h.merge(KEY => prior.merge(@proof))) # rubocop:disable Rails/SkipsModelValidations
      end
      @message.update!(status: @status, content_attributes: attributes)
      JrcCampaigns::BrokerStatusJob.enqueue_for(@message)
      true
    end
  end

  private

  def validate_proof!
    validate_shape!
    valid = UUID.match?(@proof['canonical_message_id'].to_s) && %w[sent delivered read failed].include?(@status) &&
            @proof['state'] == @status.upcase && valid_provider_id?
    raise Error, 'invalid_broker_delivery_receipt' unless valid
  end

  def validate_shape!
    valid = @proof.is_a?(Hash) && @proof.keys.sort == KEYS.sort && @proof['version'] == 1
    raise Error, 'invalid_broker_delivery_receipt' unless valid
  end

  def valid_provider_id?
    provider = @proof['provider_message_id']
    return @status == 'failed' if provider.nil?

    provider.is_a?(String) && provider.present? && provider.length <= 512 && !provider.match?(INVALID_PROVIDER_ID)
  end

  def validate_context!
    obligation = JrcBrokerWebhookObligation.find_by(message_id: @message.id, account_id: @message.account_id, inbox_id: @message.inbox_id)
    binding = obligation && JrcBrokerInboxBinding.lock.find_by(id: obligation.binding_id, account_id: @message.account_id,
                                                               inbox_id: @message.inbox_id)
    channel = @message.inbox.reload.channel
    channel.lock!
    valid = obligation && binding && channel.is_a?(Channel::Api) && obligation.current_binding? &&
            JrcBrokerWebhookObligation.deliverable_message?(@message)
    raise Error, 'broker_delivery_context_changed' unless valid
  end

  def validate_identity!(prior)
    canonical = prior['canonical_message_id']
    provider = prior['provider_message_id']
    changed = (canonical.present? && canonical != @proof['canonical_message_id']) ||
              (provider.present? && provider != @proof['provider_message_id'])
    raise Error, 'broker_delivery_identity_changed' if changed
  end

  def stale?(prior)
    current = prior['state']
    current = 'DELIVERED' if @message.delivered?
    current = 'READ' if @message.read?
    return true if %w[DELIVERED READ].include?(current) && @proof['state'] == 'FAILED'
    return false if @proof['state'] == 'FAILED'

    RANK.fetch(@proof['state'], 0) < RANK.fetch(current, 0)
  end
end
