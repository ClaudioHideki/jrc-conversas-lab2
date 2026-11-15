require 'digest'

# One native Message, one optional attachment and one durable intent key.
# Retries return the existing message; they never enqueue it a second time.
class CannedResponses::Delivery
  class Invalid < StandardError; end

  def initialize(response:, conversation:, user:)
    @response, @conversation, @user = response, conversation, user
    raise ActiveRecord::RecordNotFound unless response.account_id == conversation.account_id
  end

  def call(content:, key:, confirmed:, revision:, expected_actor_id:)
    raise Invalid, 'ACTOR_CHANGED' unless expected_actor_id == @user.id
    raise Invalid, 'CONFIRMATION_REQUIRED' unless confirmed == true
    raise Invalid, 'INVALID_DELIVERY_KEY' unless key.is_a?(String) && key.match?(/\A[a-zA-Z0-9_-]{16,80}\z/)
    raise Invalid, 'INVALID_CONTENT' unless content.is_a?(String) && content.present? && content.bytesize <= 65_536
    raise Invalid, 'UNRESOLVED_VARIABLES' if content.match?(/\[(nome|vendedor|empresa|cidade|região|data|produto\/serviço)\]|\{\{|\{%/)

    @conversation.with_lock do
      @response.reload
      digest = Digest::SHA256.hexdigest([@response.id, revision, content, @user.id].to_json)
      old = @conversation.messages.where("additional_attributes -> 'quick_reply' ->> 'key' = ?", key).first
      if old
        raise Invalid, 'DELIVERY_CONTENT_CHANGED' unless old.additional_attributes.dig('quick_reply', 'digest') == digest

        return old
      end
      raise Invalid, 'RESPONSE_CHANGED' unless revision == @response.updated_at.iso8601(6)
      raise Invalid, 'MESSAGE_WINDOW_CLOSED' unless @conversation.can_reply?
      # These channels require separate text/media messages. Do not silently partially send.
      if @response.file.attached? && %w[Channel::Instagram Channel::Tiktok].include?(@conversation.inbox.channel_type)
        raise Invalid, 'CHANNEL_REQUIRES_SEPARATE_MESSAGES'
      end

      values = {
        content: content, private: false, message_type: 'outgoing'
      }
      values[:attachments] = [@response.file.blob.signed_id] if @response.file.attached?
      message = Messages::MessageBuilder.new(@user, @conversation, values).perform
      message.update!(additional_attributes: (message.additional_attributes || {}).merge(
        'quick_reply' => { 'key' => key, 'digest' => digest, 'response_id' => @response.id }
      ))
      message
    end
  end
end
