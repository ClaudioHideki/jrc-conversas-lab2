class JrcCampaigns::BrokerMessageSender
  KINDS = %w[text image document video audio].freeze

  def self.call(delivery:, user:, phone_number:, step:, attributes:, conversation_status: 'pending', conversation: nil)
    inbox = delivery.inbox
    account = inbox.account
    raise ArgumentError, 'Tipo de mensagem não suportado pelo Broker.' unless KINDS.include?(step.fetch('kind'))
    raise ArgumentError, 'Mensagem vazia.' if step['kind'] == 'text' && step['body'].blank?
    raise ArgumentError, 'Mensagem muito longa para o Broker.' if step['body'].to_s.length > 4096

    # The record and its correlation are committed together, before message_created is dispatched.
    # Replaying a campaign job must never create a second outgoing message.
    delivery.with_lock do
      return account.messages.find(delivery.metadata['message_id']) if delivery.metadata['message_id'].present?

      contact = canonical_contact!(delivery, inbox, phone_number)
      conversation = canonical_conversation!(delivery, inbox, contact, conversation_status, preferred: conversation)
      conversation.reload if conversation.display_id.nil?
      delivery.recipient.update!(contact: contact, conversation: conversation) if delivery.is_a?(JrcCampaigns::Delivery)
      message = conversation.messages.build(account: account, inbox: inbox, sender: user, message_type: 'outgoing', content: step['body'],
                                            additional_attributes: attributes.merge('jrc_campaign_broker' => true))
      if step['kind'] != 'text'
        attach_media!(message, step, account)
      else
        message.save!
      end
      delivery.update!(external_id: "broker:#{account.id}:#{inbox.id}:#{message.id}",
                       metadata: delivery.metadata.to_h.merge('message_id' => message.id, 'conversation_id' => conversation.display_id))
      message
    end
  end

  def self.canonical_contact!(delivery, inbox, phone_number)
    recipient = campaign_recipient!(delivery, inbox)
    contact = recipient&.contact || inbox.account.contacts.find_by(phone_number: phone_number)
    contact ||= inbox.account.contacts.create!(phone_number: phone_number)
    phone = JrcCampaigns::PhoneNormalizer.call(phone_number)
    unless phone.present? && [contact.account_id, JrcCampaigns::PhoneNormalizer.call(contact.phone_number)] == [inbox.account_id, phone]
      raise ArgumentError, 'Vínculo do contato incompatível com o número destinatário.'
    end

    contact
  end

  def self.canonical_conversation!(delivery, inbox, contact, status, preferred: nil)
    conversation = selected_conversation!(delivery, inbox, contact, preferred)
    return conversation if conversation

    links = contact.contact_inboxes.where(inbox: inbox).to_a
    raise ArgumentError, 'Vínculo do contato incompatível com o número destinatário.' if links.many?

    link = links.first || contact.contact_inboxes.create!(inbox: inbox, source_id: contact.phone_number.delete_prefix('+'))
    inbox.account.conversations.create!(inbox: inbox, contact: contact, contact_inbox: link, status: status)
  end

  def self.selected_conversation!(delivery, inbox, contact, preferred)
    conversation = pinned_conversation!(delivery, preferred)
    conversation ||= preferred&.reload
    conversation ||= inbox.account.conversations.where(contact: contact, inbox: inbox).order(created_at: :desc, id: :desc).first
    if conversation && !valid_conversation?(conversation, inbox, contact)
      raise ArgumentError, 'Vínculo do contato incompatível com o número destinatário.'
    end

    conversation
  end

  def self.pinned_conversation!(delivery, preferred)
    return unless delivery.is_a?(JrcCampaigns::Delivery)

    conversation = delivery.recipient.conversation
    raise ArgumentError, 'A conversa escolhida mudou. Revise uma nova prévia.' if conversation && preferred && conversation.id != preferred.id

    conversation
  end

  def self.campaign_recipient!(delivery, inbox)
    return unless delivery.is_a?(JrcCampaigns::Delivery)

    recipient = delivery.recipient
    unless [recipient.campaign.account_id, recipient.inbox_id] == [inbox.account_id, inbox.id]
      raise ArgumentError, 'Vínculo do contato incompatível com o número destinatário.'
    end

    recipient
  end

  def self.valid_conversation?(conversation, inbox, contact)
    link = conversation.contact_inbox
    link && [conversation.account_id, conversation.inbox_id, conversation.contact_id] == [inbox.account_id, inbox.id, contact.id] &&
      [link.contact_id, link.inbox_id] == [contact.id, inbox.id] && link.source_id.present?
  end

  def self.attach_media!(message, step, account)
    file_type = { 'image' => 'image', 'audio' => 'audio', 'video' => 'video' }.fetch(step['kind'], 'file')
    if step['media_asset_id'].present?
      asset = account.jrc_campaign_media_assets.find(step['media_asset_id'])
      raise ArgumentError, 'Arquivo incompatível ou maior que 10 MB.' unless asset.kind == step['kind'] && asset.file.byte_size <= 10.megabytes

      normalized_file = JrcCampaigns::BrokerImageNormalizer.call(kind: step['kind'], file: asset.file.blob)
      message.attachments.build(account: account, file_type: file_type, file: normalized_file)
      return message.save!
    end
    # This user-controlled URL must always use the public-network SSRF guard.
    raise ArgumentError, 'Importe a mídia pela biblioteca de arquivos da campanha.' if SafeFetch.allow_private_network?

    SafeFetch.fetch(step.fetch('media_url'), max_bytes: 10.megabytes, open_timeout: 5, read_timeout: 20,
                    allowed_content_type_prefixes: step['kind'] == 'document' ? [] : ["#{step['kind']}/"],
                    allowed_content_types: step['kind'] == 'document' ? %w[application/pdf application/octet-stream text/plain] : []) do |file|
      source = { io: file.tempfile, filename: step['file_name'].presence || file.filename, content_type: file.content_type }
      normalized_file = JrcCampaigns::BrokerImageNormalizer.call(kind: step['kind'], file: source)
      message.attachments.build(account: account, file_type: file_type, file: normalized_file)
      message.save!
    end
  rescue SafeFetch::Error, Timeout::Error
    raise ArgumentError, 'Não foi possível obter uma mídia pública do tipo selecionado com até 10 MB.'
  end
  private_class_method :canonical_contact!, :canonical_conversation!, :selected_conversation!, :pinned_conversation!,
                       :campaign_recipient!, :valid_conversation?, :attach_media!
end
