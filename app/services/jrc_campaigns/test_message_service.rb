class JrcCampaigns::TestMessageService
  CampaignContext = Data.define(:account)
  RecipientContext = Data.define(:campaign, :contact, :name, :phone_number, :email)

  def initialize(account:, user:, delivery_channel: 'whatsapp', phone_number: nil, email: nil, inbox_id:, step:,
                 idempotency_key: nil, operator_confirmed: false)
    @account = account
    @user = user
    @delivery_channel = delivery_channel.presence || 'whatsapp'
    @phone_number = JrcCampaigns::PhoneNormalizer.call(phone_number)
    @email = JrcCampaigns::EmailNormalizer.call(email)
    @inbox = account.inboxes.includes(:channel).find(inbox_id)
    @step = step.to_h.with_indifferent_access
    @idempotency_key = idempotency_key
    @operator_confirmed = operator_confirmed
  end

  def perform
    unless JrcCampaigns::Campaign::DELIVERY_CHANNELS.include?(delivery_channel)
      raise ArgumentError, 'Canal de envio inválido.'
    end
    return send_email if delivery_channel == 'email'

    send_whatsapp
  end

  private

  attr_reader :account, :user, :delivery_channel, :phone_number, :email, :inbox, :step

  def send_whatsapp
    raise ArgumentError, 'Informe um número válido para o teste.' if phone_number.blank?
    connector = JrcCampaigns::EvolutionConnector.for(inbox)
    return send_evolution(connector) if connector

    raise ArgumentError, 'A caixa selecionada não é WhatsApp.' unless channel.is_a?(Channel::Whatsapp)

    eligibility = JrcCampaigns::EligibilityPolicy.new(account: account, phone_number: phone_number)
    rejection = eligibility.rejection_reason
    raise ArgumentError, rejection if rejection
    eligibility.freeform_conversation!(inbox) unless step[:kind] == 'template'

    message_id = step[:kind] == 'template' ? send_template : send_freeform
    raise StandardError, proxy.external_error.presence || 'O provedor não confirmou o envio do teste.' if message_id.blank?

    { message_id: message_id, inbox_id: inbox.id, phone_number: phone_number, delivery_channel: 'whatsapp' }
  end

  def send_email
    result = JrcCampaigns::EmailSender.new(
      account: account,
      user: user,
      inbox: inbox,
      email: email,
      name: user.name,
      subject: renderer.render(effective_value(:subject)),
      body: renderer.render(effective_value(:body)),
      media_asset_id: effective_value(:media_asset_id),
      conversation_status: 'open',
      additional_attributes: { 'jrc_campaign_test' => true }
    ).perform
    {
      message_id: result[:external_id],
      inbox_id: inbox.id,
      email: email,
      delivery_channel: 'email'
    }
  end

  def send_evolution(connector)
    rendered_step = %w[kind body media_url file_name].index_with { |key| renderer.render(effective_value(key)) }
    JrcCampaigns::EvolutionTestService.new(
      connector: connector, user: user, phone_number: phone_number, step: rendered_step,
      idempotency_key: @idempotency_key, operator_confirmed: @operator_confirmed
    ).perform
  end

  def channel
    inbox.channel
  end

  def renderer
    campaign = CampaignContext.new(account: account)
    recipient = RecipientContext.new(
      campaign: campaign,
      contact: nil,
      name: user.name,
      phone_number: phone_number,
      email: email
    )
    @renderer ||= JrcCampaigns::TemplateRenderer.new(recipient: recipient, inbox: inbox)
  end

  def proxy
    @proxy ||= JrcCampaigns::ProviderMessageProxy.new(
      kind: step[:kind],
      body: renderer.render(effective_value(:body)),
      media_url: effective_value(:media_url),
      file_name: effective_value(:file_name)
    )
  end

  def send_freeform
    channel.send_message(phone_number, proxy)
  end

  def send_template
    raw_params = effective_value(:template_params).to_h.deep_stringify_keys
    raw_params['name'] = effective_value(:template_name)
    raw_params['namespace'] = effective_value(:template_namespace)
    raw_params['language'] = effective_value(:template_language)
    name, namespace, lang_code, parameters = Whatsapp::TemplateProcessorService.new(
      channel: channel,
      template_params: renderer.render(raw_params)
    ).call
    raise ArgumentError, 'Template não aprovado ou não encontrado na caixa selecionada.' if name.blank?

    channel.send_template(
      phone_number,
      { name: name, namespace: namespace, lang_code: lang_code, parameters: parameters },
      proxy
    )
  end

  def effective_value(field)
    overrides = step[:inbox_overrides].to_h.with_indifferent_access
    inbox_override = overrides[inbox.id.to_s].to_h.with_indifferent_access
    inbox_override[field].presence || step[field]
  end
end
