require 'digest'

class JrcCampaigns::TemplateMediaService
  def initialize(inbox:, user:, name:, language:)
    @inbox = inbox
    @user = user
    @name = name
    @language = language
  end

  def perform
    JrcCampaigns::OfficialMetaRoute.assert!(@inbox)
    raise ArgumentError, 'Selecione uma caixa WhatsApp oficial.' unless @inbox.channel.is_a?(Channel::Whatsapp)

    template = Array(@inbox.channel.message_templates).find do |item|
      item['name'] == @name && item['language'].to_s.casecmp?(@language.to_s) && item['status'].to_s.casecmp?('approved')
    end
    raise ArgumentError, 'Template não encontrado ou não aprovado.' unless template
    header = Array(template['components']).find { |component| component['type'].to_s.casecmp?('HEADER') }
    kind = header.to_h['format'].to_s.downcase
    raise ArgumentError, 'Template sem exemplo de mídia suportada. Importe o arquivo manualmente.' unless JrcCampaigns::MetaMedia::TYPES.key?(kind)

    handle = Array(header.dig('example', 'header_handle')).first.to_s
    key = Digest::SHA256.hexdigest([@inbox.id, @name, @language, kind, handle].to_json)
    asset = @inbox.account.jrc_campaign_media_assets.find_by(source_key: key)
    if asset
      JrcCampaigns::MetaMedia.validate!(asset)
      return asset
    end
    JrcCampaigns::MetaMedia.import!(account: @inbox.account, user: @user, kind: kind, url: handle, source_key: key)
  rescue ActiveRecord::RecordNotUnique
    # Concurrent selections share the account-owned asset. Never reuse across tenants.
    @inbox.account.jrc_campaign_media_assets.find_by!(source_key: key)
  end
end
