# frozen_string_literal: true

class JrcServiceDesk::NotificationPayload
  def initialize(message, row)
    @message = message
    @row = row
  end

  def digest
    fields = identity.merge(content, authorization)
    if @row.source_digest.present?
      fields.merge!('source_digest' => @row.source_digest, 'attempt_number' => @row.attempt_number,
                    'original_delivery_id' => @row.original_delivery_id)
    end
    JrcServiceDesk::CanonicalJson.digest(fields)
  end

  private

  def identity
    { 'account_id' => @message.account_id, 'inbox_id' => @message.inbox_id, 'conversation_id' => @message.conversation_id,
      'contact_id' => @message.conversation.contact_id, 'contact_inbox_id' => @message.conversation.contact_inbox_id,
      'sender_id' => @message.sender_id, 'sender_type' => @message.sender_type }
  end

  def content
    { 'content' => @message.content, 'private' => @message.private?, 'message_type' => @message.message_type,
      'content_type' => @message.content_type, 'content_attributes' => @message.content_attributes.to_h,
      'additional_attributes' => @message.additional_attributes.to_h, 'attachments' => attachments }
  end

  def attachments
    @message.attachments.order(:id).map { |file| [file.id, file.file.blob&.checksum, file.file.blob&.byte_size] }
  end

  def authorization
    { 'to_emails' => @message.content_attributes.to_h['to_emails'], 'recipient' => @row.recipient,
      'policy_id' => @row.notification_policy_version_id, 'policy_digest' => @row.notification_policy_version&.digest }
  end
end
