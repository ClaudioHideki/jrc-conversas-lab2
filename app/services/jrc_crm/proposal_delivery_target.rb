class JrcCrm::ProposalDeliveryTarget
  attr_reader :contact, :inbox, :template_params

  def initialize(proposal:, actor:, delivery:, public_url:)
    @proposal = proposal
    @actor = actor
    @delivery = delivery.deep_stringify_keys
    @public_url = public_url
    @template_params = @delivery['template_params'].presence&.deep_dup
  end

  def authorize!
    account = @proposal.account
    member = account.account_users.find_by!(user_id: @actor.id)
    @context = { account: account, user: @actor, account_user: member }
    @contact = account.contacts.find(@delivery.fetch('contact_id'))
    @inbox = account.inboxes.find(@delivery.fetch('inbox_id'))
    validate_access!
    validate_recipient!
  end

  def conversation
    existing = contact.conversations.where(account_id: @proposal.account_id, inbox_id: inbox.id, status: 'open')
                      .order(updated_at: :desc).first
    return existing if existing && authorized_conversation?(existing)

    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: inbox, source_id: nil).perform
    candidate = ConversationBuilder.new(contact_inbox: contact_inbox,
                                        params: ActionController::Parameters.new(assignee_id: @actor.id, status: 'open')).perform
    raise Pundit::NotAuthorizedError unless authorized_conversation?(candidate)

    candidate
  end

  def authorized_conversation?(conversation)
    conversation.account_id == @proposal.account_id && conversation.contact_id == contact.id &&
      conversation.inbox_id == inbox.id && ConversationPolicy.new(@context, conversation).show?
  end

  def validate_message!(conversation)
    if template_params.present?
      validate_template!
    elsif !conversation.can_reply?
      raise ArgumentError, 'Este canal exige um modelo WhatsApp aprovado para iniciar ou retomar a conversa.'
    end
  end

  def content
    message = @delivery['content'].to_s.strip
    return message if template_params.present?

    message = "Olá #{contact.name}, segue sua proposta comercial JRC:" if message.blank?
    return message if message.include?(@public_url)

    "#{message}\n\n#{@public_url}\n\nO PDF da proposta está anexado a esta mensagem."
  end

  private

  def validate_access!
    member = @context[:account_user]
    raise Pundit::NotAuthorizedError if member.custom_role_id.present? && member.permissions.exclude?('contact_manage')
    raise Pundit::NotAuthorizedError unless ContactPolicy.new(@context, contact).show?
    raise Pundit::NotAuthorizedError unless @actor.assigned_inboxes.where(account_id: @proposal.account_id).exists?(id: inbox.id)
  end

  def validate_recipient!
    raise ArgumentError, 'Selecione uma caixa WhatsApp autorizada.' unless whatsapp_inbox?
    raise ArgumentError, 'Cadastre o telefone com código do país para enviar por WhatsApp.' if contact.phone_number.blank?
    raise ArgumentError, 'O destinatário está bloqueado para receber mensagens.' if contact.blocked?
  end

  def whatsapp_inbox?
    inbox.whatsapp? || inbox.twilio_whatsapp? || (inbox.api? && inbox.name.match?(/whatsapp/i))
  end

  def validate_template!
    raise ArgumentError, 'Parâmetros do modelo WhatsApp inválidos.' unless template_params.is_a?(Hash)

    parameters = processed_template_parameters
    raise ArgumentError, 'Selecione um modelo WhatsApp aprovado neste canal.' if parameters.blank?
    return if parameters.to_json.include?(@public_url)

    raise ArgumentError, 'Inclua o link desta proposta em um parâmetro do modelo WhatsApp antes de enviar.'
  end

  def processed_template_parameters
    if inbox.whatsapp?
      Whatsapp::TemplateProcessorService.new(channel: inbox.channel, template_params: template_params.deep_dup).call.last
    elsif inbox.twilio_whatsapp?
      Twilio::TemplateProcessorService.new(channel: inbox.channel, template_params: template_params.deep_dup).call.last
    end
  end
end
