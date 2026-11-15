require 'digest'

# One native Message, one optional attachment and one durable intent key.
# Retries return the existing message; they never enqueue it a second time.
class CannedResponses::Delivery
  class Invalid < StandardError; end

  # Match the existing public ReplyBox limits; direct review cannot bypass them.
  MAX_CONTENT_LENGTH = {
    'Channel::FacebookPage' => 2000, 'Channel::Instagram' => 1000, 'Channel::Telegram' => 4096,
    'Channel::Tiktok' => 6000, 'Channel::Sms' => 320, 'Channel::Email' => 25_000, 'Channel::Whatsapp' => 4096
  }.freeze

  def initialize(response:, conversation:, user:)
    @response, @conversation, @user = response, conversation, user
    raise ActiveRecord::RecordNotFound unless response.account_id == conversation.account_id
  end

  def call(content:, key:, confirmed:, revision:, expected_actor_id:)
    raise Invalid, 'ACTOR_CHANGED' unless expected_actor_id == @user.id
    raise Invalid, 'CONFIRMATION_REQUIRED' unless confirmed == true
    raise Invalid, 'INVALID_DELIVERY_KEY' unless key.is_a?(String) && key.match?(/\A[a-zA-Z0-9_-]{16,80}\z/)
    raise Invalid, 'INVALID_CONTENT' unless content.is_a?(String) && content.present? && content.bytesize <= 65_536
    raise Invalid, 'CONTENT_TOO_LONG' if content.encode(Encoding::UTF_16LE).bytesize / 2 > max_content_length
    raise Invalid, 'UNRESOLVED_VARIABLES' if content.match?(/\[(nome|vendedor|empresa|cidade|região|data|produto\/serviço)\]|\{\{|\{%/)

    values = { content: content, key: key, revision: revision }
    return perform(**values, upload: nil, source_blob: nil) unless @response.file.attached?

    blob = @response.file.blob
    JrcServiceDesk::OutboundAttachments.authorize_blob!(blob, user: @user, account_id: @conversation.account_id)
    # Keep the native checked tempfile open through the Message transaction and
    # its upload callbacks. Each message owns a copy, so a later SD link cannot
    # change the authority of the shared model's original blob.
    blob.open do |file|
      upload = ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: blob.filename.to_s, type: blob.content_type)
      perform(**values, upload: upload, source_blob: blob)
    end
  end

  private

  def max_content_length
    inbox = @conversation.inbox
    return inbox.twilio_whatsapp? ? 1600 : 320 if inbox.twilio?

    MAX_CONTENT_LENGTH.fetch(inbox.channel_type, 10_000)
  end

  def perform(content:, key:, revision:, upload:, source_blob:)
    @conversation.with_lock do
      @response.lock!
      digest = Digest::SHA256.hexdigest([@response.id, revision, content, @user.id].to_json)
      old = @conversation.messages.where("additional_attributes -> 'quick_reply' ->> 'key' = ?", key).first
      if old
        raise Invalid, 'DELIVERY_CONTENT_CHANGED' unless old.additional_attributes.dig('quick_reply', 'digest') == digest

        return old
      end
      current_blob_id = @response.file.attached? ? @response.file.blob_id : nil
      raise Invalid, 'RESPONSE_CHANGED' unless revision == @response.updated_at.iso8601(6) && current_blob_id == source_blob&.id
      raise Invalid, 'MESSAGE_WINDOW_CLOSED' unless @conversation.can_reply?
      # These channels require separate text/media messages. Do not silently partially send.
      if @response.file.attached? && %w[Channel::Instagram Channel::Tiktok].include?(@conversation.inbox.channel_type)
        raise Invalid, 'CHANNEL_REQUIRES_SEPARATE_MESSAGES'
      end

      values = {
        content: content, private: false, message_type: 'outgoing'
      }
      if upload
        JrcServiceDesk::OutboundAttachments.authorize_blob!(source_blob.reload, user: @user, account_id: @conversation.account_id)
        values[:attachments] = [upload]
      end
      message = Messages::MessageBuilder.new(@user, @conversation, values).perform
      message.update!(additional_attributes: (message.additional_attributes || {}).merge(
        'quick_reply' => { 'key' => key, 'digest' => digest, 'response_id' => @response.id }
      ))
      message
    end
  end
end
