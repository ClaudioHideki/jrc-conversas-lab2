class JrcCampaigns::OfficialMetaRoute
  def self.assert!(inbox)
    return unless inbox.channel_type == 'Channel::Whatsapp' && inbox.channel.provider == 'whatsapp_cloud'

    Whatsapp::CloudApiEndpoint.base_url
    return if inbox.channel.provider_service.is_a?(Whatsapp::Providers::WhatsappCloudService)

    raise ArgumentError,
          'Provider oficial incompatível com a caixa selecionada.'
  end
end
