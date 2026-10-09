# frozen_string_literal: true

# An explicit published native incoming message; never a latest-message lookup.
class JrcRelationship::PlaybookFlowInput
  FIELDS = %w[id account_id conversation_id inbox_id sender_type sender_id content private message_type content_type].freeze

  def self.find!(account:, conversation:, contact_id:, message_id:)
    raise ArgumentError, 'Explicit native incoming message ID required' unless message_id.is_a?(Integer) && message_id.positive?

    message = Message.where(account_id: account.id, conversation_id: conversation.id, inbox_id: conversation.inbox_id).find(message_id)
    raise Pundit::NotAuthorizedError unless native_contact_message?(message, contact_id)

    message
  end

  def self.native_contact_message?(message, contact_id)
    message.incoming? && !message.private? && message.sender_type == 'Contact' && message.sender_id == contact_id &&
      message.content_attributes.to_h['jrc_flow_run_id'].blank?
  end
  private_class_method :native_contact_message?

  def self.digest(message)
    JrcRelationship::PlaybookFlowReference.digest(
      'message' => message.attributes.slice(*FIELDS), 'attachment_ids' => message.attachments.ids.sort
    )
  end
end
