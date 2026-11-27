class JrcCampaigns::TestMessageService
  CampaignContext = Data.define(:account)
  RecipientContext = Data.define(:campaign, :contact, :name, :phone_number, :email)

  def initialize(account:, user:, inbox_id:, step:, delivery_channel: 'whatsapp', phone_number: nil, email: nil,
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
    raise ArgumentError, 'Canal de envio inválido.' unless JrcCampaigns::Campaign::DELIVERY_CHANNELS.include?(delivery_channel)
    return send_email if delivery_channel == 'email'

    send_whatsapp
  end

  private

  attr_reader :account, :user, :delivery_channel, :phone_number, :email, :inbox, :step

  def send_whatsapp
    raise ArgumentError, 'Informe um número válido para o teste.' if phone_number.blank?

    connector = JrcCampaigns::EvolutionConnector.for(inbox) if inbox.channel_type == 'Channel::Api'
    return send_evolution(connector) if connector

    broker = JrcCampaigns::BrokerConnector.for(inbox) if inbox.channel_type == 'Channel::Api'
    if broker
      return JrcCampaigns::BrokerTestService.new(connector: broker, user: user, phone_number: phone_number,
                                                 step: %w[kind body media_url file_name media_asset_id].index_with do |key|
                                                   renderer.render(effective_value(key))
                                                 end,
                                                 idempotency_key: @idempotency_key, operator_confirmed: @operator_confirmed).perform
    end

    raise ArgumentError, 'A caixa selecionada não é WhatsApp.' unless channel.is_a?(Channel::Whatsapp)

    values = step.deep_stringify_keys
    values.merge!(values.fetch('inbox_overrides', {}).fetch(inbox.id.to_s, {}))
    JrcCampaigns::OfficialTestService.new(inbox: inbox, user: user, phone_number: phone_number, step: values, renderer: renderer,
                                          idempotency_key: @idempotency_key, operator_confirmed: @operator_confirmed).perform
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
    asset_id = effective_value('media_asset_id')
    rendered_step['media_asset_id'] = asset_id if asset_id.present?
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

  def effective_value(field)
    overrides = step[:inbox_overrides].to_h.with_indifferent_access
    inbox_override = overrides[inbox.id.to_s].to_h.with_indifferent_access
    inbox_override[field].presence || step[field]
  end
end
