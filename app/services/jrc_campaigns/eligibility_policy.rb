class JrcCampaigns::EligibilityPolicy
  def initialize(account:, phone_number:, contact: nil, purpose: nil)
    @account = account
    @phone_number = JrcCampaigns::PhoneNormalizer.call(phone_number)
    @contact = contact
    @purpose = purpose
  end

  def rejection_reason
    safety_reason = safety_rejection_reason
    return safety_reason if safety_reason

    consent = JrcCampaigns::Consent.active.where(account: account, phone_number: phone_number)
    return 'Consentimento positivo não registrado ou revogado.' unless consent.exists?
    return 'Consentimento sem finalidade confirmada para campanhas e testes WhatsApp.' if @purpose && !consent.exists?(purpose: @purpose)

    nil
  end

  def safety_rejection_reason
    return 'Telefone inválido.' unless phone_number.match?(/\A\+[1-9]\d{7,14}\z/)
    return 'Destinatário na blacklist.' if account.jrc_campaign_blacklists.exists?(phone_number: phone_number)
    return 'Contato bloqueado.' if blocked?

    nil
  end

  # QR campaigns use the explicitly selected list, without manufacturing consent.
  # A recorded withdrawal still wins over a subsequent CSV/manual import.
  def list_rejection_reason
    reason = safety_rejection_reason
    return reason if reason

    records = JrcCampaigns::Consent.where(account: account, phone_number: phone_number)
    if records.where.not(revoked_at: nil).exists? && !records.active.exists?
      return 'Consentimento positivo revogado para este destinatário.'
    end

    nil
  end

  def freeform_conversation!(inbox)
    conversation = conversation_for_phone(inbox)
    unless conversation && Conversations::MessageWindowService.new(conversation).can_reply?
      raise ArgumentError, 'Mensagem livre fora da janela de atendimento; use template aprovado da Meta.'
    end

    conversation
  end

  private

  attr_reader :account, :phone_number, :contact

  def conversation_for_phone(inbox)
    existing_contact = contact || account.contacts.find_by(phone_number: phone_number)
    return unless existing_contact

    links = existing_contact.contact_inboxes.where(inbox: inbox).select do |link|
      JrcCampaigns::PhoneNormalizer.call(link.source_id) == phone_number
    end
    existing_contact.conversations.where(inbox: inbox, contact_inbox_id: links.map(&:id)).order(updated_at: :desc).first
  end

  def blocked?
    contact&.reload&.blocked? || blocked_phone?
  end

  def blocked_phone?
    account.contacts.where(blocked: true).where.not(phone_number: [nil, '']).pluck(:phone_number).any? do |number|
      JrcCampaigns::PhoneNormalizer.call(number) == phone_number
    end
  end
end
