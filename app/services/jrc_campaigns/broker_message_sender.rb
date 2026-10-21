class JrcCampaigns::BrokerMessageSender
  KINDS = %w[text image document video audio].freeze

  def self.call(delivery:, user:, phone_number:, step:, attributes:, conversation_status: 'pending')
    inbox = delivery.inbox
    account = inbox.account
    raise ArgumentError, 'Tipo de mensagem não suportado pelo Broker.' unless KINDS.include?(step.fetch('kind'))
    raise ArgumentError, 'Mensagem vazia.' if step['kind'] == 'text' && step['body'].blank?
    raise ArgumentError, 'Mensagem muito longa para o Broker.' if step['body'].to_s.length > 4096

    # The record and its correlation are committed together, before message_created is dispatched.
    # Replaying a campaign job must never create a second outgoing message.
    delivery.with_lock do
      return account.messages.find(delivery.metadata['message_id']) if delivery.metadata['message_id'].present?

      contact = account.contacts.find_by(phone_number: phone_number) || account.contacts.create!(phone_number: phone_number)
      link = contact.contact_inboxes.find_or_create_by!(inbox: inbox) { |item| item.source_id = phone_number.delete_prefix('+') }
      unless JrcCampaigns::PhoneNormalizer.call(link.source_id.to_s.split('@').first) == phone_number
        raise ArgumentError, 'Vínculo do contato incompatível com o número destinatário.'
      end
      conversation = contact.conversations.where(inbox: inbox, contact_inbox: link).order(created_at: :desc).first
      conversation ||= account.conversations.create!(inbox: inbox, contact: contact, contact_inbox: link, status: conversation_status)
      conversation.reload if conversation.display_id.nil?
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

  def self.attach_media!(message, step, account)
    file_type = { 'image' => 'image', 'audio' => 'audio', 'video' => 'video' }.fetch(step['kind'], 'file')
    if step['media_asset_id'].present?
      asset = account.jrc_campaign_media_assets.find(step['media_asset_id'])
      raise ArgumentError, 'Arquivo incompatível ou maior que 10 MB.' unless asset.kind == step['kind'] && asset.file.byte_size <= 10.megabytes

      message.attachments.build(account: account, file_type: file_type, file: asset.file.blob)
      return message.save!
    end
    # This user-controlled URL must always use the public-network SSRF guard.
    raise ArgumentError, 'Importe a mídia pela biblioteca de arquivos da campanha.' if SafeFetch.allow_private_network?

    SafeFetch.fetch(step.fetch('media_url'), max_bytes: 10.megabytes, open_timeout: 5, read_timeout: 20,
                    allowed_content_type_prefixes: step['kind'] == 'document' ? [] : ["#{step['kind']}/"],
                    allowed_content_types: step['kind'] == 'document' ? %w[application/pdf application/octet-stream text/plain] : []) do |file|
      message.attachments.build(account: account, file_type: file_type,
                                file: { io: file.tempfile, filename: step['file_name'].presence || file.filename, content_type: file.content_type })
      message.save!
    end
  rescue SafeFetch::Error, Timeout::Error
    raise ArgumentError, 'Não foi possível obter uma mídia pública do tipo selecionado com até 10 MB.'
  end
  private_class_method :attach_media!
end
