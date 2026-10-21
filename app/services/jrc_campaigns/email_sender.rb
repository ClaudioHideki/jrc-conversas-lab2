class JrcCampaigns::EmailSender
  def initialize(account:, user:, inbox:, email:, name:, subject:, body:, media_asset_id: nil, conversation: nil,
                 conversation_status: 'pending', additional_attributes: {})
    @account = account
    @user = user
    @inbox = inbox
    @email = JrcCampaigns::EmailNormalizer.call(email)
    @name = name
    @subject = subject.to_s.gsub(/[\r\n]+/, ' ').strip
    @body = body.to_s
    @media_asset_id = media_asset_id
    @conversation = conversation
    @conversation_status = conversation_status
    @additional_attributes = additional_attributes
  end

  def perform
    validate!
    contact = find_or_create_contact
    conversation = find_or_create_conversation(contact)
    message = build_message(conversation)
    begin
      delivered_mail = ConversationReplyMailer.with(account: account).email_reply(message).deliver_now
      external_id = delivered_mail&.message_id
      raise 'A caixa de e-mail não confirmou o envio. Verifique SMTP/OAuth.' if external_id.blank?

      message.update!(source_id: external_id, status: 'sent')
      { external_id: external_id, message: message, conversation: conversation, contact: contact }
    rescue StandardError => e
      message.update!(status: 'failed', content_attributes: message.content_attributes.to_h.merge('external_error' => e.message))
      raise
    end
  end

  private

  attr_reader :account, :user, :inbox, :email, :name, :subject, :body, :media_asset_id,
              :conversation_status, :additional_attributes

  def validate!
    raise ArgumentError, 'Informe um e-mail válido.' if email.blank?
    raise ArgumentError, 'A caixa selecionada não é de e-mail.' unless inbox.channel.is_a?(Channel::Email)
    raise ArgumentError, 'Informe o assunto do e-mail.' if subject.blank?
    raise ArgumentError, 'Informe o conteúdo do e-mail.' if body.blank?
  end

  def find_or_create_contact
    account.contacts.from_email(email) || account.contacts.create!(
      name: name.presence || email.split('@').first,
      email: email
    )
  end

  def find_or_create_conversation(contact)
    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: inbox).perform
    conversation = @conversation
    conversation ||= Conversation.create!(
      account: account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      status: conversation_status,
      additional_attributes: { 'source' => 'email', 'mail_subject' => subject }
    )
    conversation.update!(
      additional_attributes: conversation.additional_attributes.to_h.merge('mail_subject' => subject)
    )
    conversation
  end

  def build_message(conversation)
    placeholder_id = "jrc-email-pending-#{SecureRandom.uuid}"
    params = {
      content: body,
      message_type: 'outgoing',
      to_emails: email,
      source_id: placeholder_id,
      campaign_id: message_campaign_id,
      attachments: attachment_signed_ids
    }
    message = Messages::MessageBuilder.new(user, conversation, params).perform
    message.update!(
      additional_attributes: message.additional_attributes.to_h.merge(additional_attributes.stringify_keys)
    )
    message
  end

  def attachment_signed_ids
    return [] if media_asset_id.blank?

    asset = account.jrc_campaign_media_assets.find_by(id: media_asset_id)
    return [] unless asset&.file&.attached?

    [asset.file.blob.signed_id]
  end

  def message_campaign_id
    attributes = additional_attributes.with_indifferent_access
    attributes[:campaign_id].presence || ('jrc-campaign-test' if attributes[:jrc_campaign_test])
  end
end
