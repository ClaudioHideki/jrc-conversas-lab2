# frozen_string_literal: true

# Uses the native widget's Message/Attachment creation path. The authenticated
# Contact remains the sender; no operator identity or outgoing builder is used.
class JrcServiceDesk::PortalCustomerMessage
  include FileTypeHelper

  def self.create!(**attributes)
    new.create!(**attributes)
  end

  def create!(conversation:, contact:, **attributes)
    validate_message_fields!(attributes)
    authorize_identity!(conversation, contact)

    files = attributes.fetch(:files, [])
    JrcServiceDesk::InteractionAttachments.prepare(files)
    JrcServiceDesk::NativeExecutionContext.with(account: conversation.account, contact: contact, inbox: conversation.inbox) do
      message = conversation.messages.new(account_id: conversation.account_id, inbox_id: conversation.inbox_id, sender: contact,
                                          content: attributes[:content], source_id: attributes[:source_id], message_type: :incoming, private: false,
                                          content_attributes: attributes[:content_attributes])
      files.each do |uploaded|
        message.attachments.new(account_id: message.account_id, file: uploaded, file_type: file_type(uploaded.content_type))
      end
      message.save!
      mark_unscanned_attachments(message)
      message
    end
  end

  private

  def authorize_identity!(conversation, contact)
    raise Pundit::NotAuthorizedError unless conversation.contact_id == contact.id && conversation.account_id == contact.account_id &&
                                            conversation.inbox.channel_type == 'Channel::WebWidget'
  end

  def validate_message_fields!(attributes)
    required = %i[content source_id content_attributes]
    unknown = attributes.keys - required - [:files]
    raise ArgumentError, 'Explicit native message fields required' unless unknown.empty? && required.all? { |key| attributes.key?(key) }
  end

  def mark_unscanned_attachments(message)
    message.attachments.each do |attachment|
      blob = attachment.file.blob
      blob.update!(metadata: blob.metadata.merge('service_desk_scan_state' => 'unavailable'))
    end
  end
end
