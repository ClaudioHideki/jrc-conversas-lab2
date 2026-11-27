class JrcCampaigns::TemplateConfiguration
  MEDIA_TYPES = %w[image video document].freeze
  SUPPORTED_COMPONENTS = %w[HEADER BODY FOOTER BUTTONS].freeze
  SUPPORTED_BUTTONS = %w[URL PHONE_NUMBER QUICK_REPLY].freeze

  def initialize(inbox:, step:)
    @inbox = inbox
    @step = step.to_h.deep_stringify_keys
    override = @step.fetch('inbox_overrides', {}).to_h[inbox.id.to_s].to_h
    @step.merge!(override)
  end

  def validate!
    JrcCampaigns::OfficialMetaRoute.assert!(inbox)
    raise ArgumentError, 'Template Meta exige uma caixa WhatsApp oficial.' unless inbox.channel.is_a?(Channel::Whatsapp)

    template = Array(inbox.channel.message_templates).find do |item|
      item['name'] == step['template_name'] && item['language'].to_s.casecmp?(step['template_language'].to_s)
    end
    unless template && template['status'].to_s.casecmp?('approved')
      raise ArgumentError,
            'Template não encontrado ou não aprovado. Atualize o catálogo da caixa.'
    end

    params = step['template_params'] || {}
    raise ArgumentError, 'Parâmetros do template devem ser um objeto JSON.' unless params.is_a?(Hash)

    @processed = params.fetch('processed_params', {})
    raise ArgumentError, 'processed_params deve ser um objeto JSON.' unless processed.is_a?(Hash)
    raise ArgumentError, 'Componente de parâmetros não suportado.' if (processed.keys - %w[header body buttons]).any?

    sections = Array(template['components']).map { |component| component['type'].to_s.downcase }
    processed.each do |key, value|
      raise ArgumentError, "O componente #{key} não existe no template aprovado." if value.present? && !sections.include?(key)
    end

    Array(template['components']).each { |component| validate_component!(component) }
    template
  end

  # Uses the same approved definition and processor for validation, tests and campaigns.
  # Files are retained in account-owned ActiveStorage, not Meta's example handles.
  def payload(renderer: nil)
    validate!
    params = step.fetch('template_params', {}).deep_dup
    params['processed_params']&.compact_blank!
    params['name'] = step['template_name']
    params['namespace'] = step['template_namespace']
    params['language'] = step['template_language']
    # Positional components are ordered by parameter number, not JSON insertion order.
    %w[header body].each do |section|
      data = params.dig('processed_params', section)
      next unless data.is_a?(Hash) && data.keys.all? { |key| key.match?(/\A\d+\z/) }

      params['processed_params'][section] = data.sort_by { |key, _| key.to_i }.to_h
    end
    params = renderer.render(params) if renderer
    self.class.new(inbox: inbox, step: step.merge('template_params' => params)).validate!

    header = params.dig('processed_params', 'header')
    if header && MEDIA_TYPES.include?(header['media_type'])
      asset_id = header.delete('media_asset_id') || step['media_asset_id']
      asset = inbox.account.jrc_campaign_media_assets.find(asset_id)
      JrcCampaigns::MetaMedia.validate!(asset)
      raise ArgumentError, 'Arquivo incompatível com o cabeçalho aprovado.' unless asset.kind == header['media_type']

      header['media_url'] = Rails.application.routes.url_helpers.rails_blob_url(asset.file, host: ENV.fetch('FRONTEND_URL'))
      header['media_name'] = asset.file.filename.to_s if asset.kind == 'document'
    end
    name, namespace, lang_code, parameters = Whatsapp::TemplateProcessorService.new(channel: inbox.channel, template_params: params).call
    raise ArgumentError, 'Template indisponível para esta caixa ou permissão.' if name.blank?

    { name: name, namespace: namespace, lang_code: lang_code, parameters: parameters }
  end

  private

  attr_reader :inbox, :step, :processed

  def validate_component!(component)
    type = component['type'].to_s.upcase
    raise ArgumentError, "Componente de template não suportado: #{type}." unless SUPPORTED_COMPONENTS.include?(type)

    case type
    when 'HEADER' then validate_header!(component)
    when 'BODY' then validate_variables!(component, 'body')
    when 'BUTTONS' then validate_buttons!(component)
    end
  end

  def validate_header!(component)
    format = component['format'].to_s.downcase
    return validate_variables!(component, 'header') if format == 'text'
    raise ArgumentError, "Cabeçalho não suportado: #{format}." unless MEDIA_TYPES.include?(format)

    header = processed['header']
    unless header.is_a?(Hash) && header['media_type'] == format && (header['media_asset_id'].present? || step['media_asset_id'].present?)
      raise ArgumentError, "Importe uma mídia #{format} para o cabeçalho obrigatório."
    end

    extra = header.keys - %w[media_type media_asset_id media_url media_name]
    raise ArgumentError, 'Parâmetro de cabeçalho de mídia incompatível.' if extra.any?

    asset = inbox.account.jrc_campaign_media_assets.find(header['media_asset_id'] || step['media_asset_id'])
    raise ArgumentError, 'Arquivo incompatível com o cabeçalho aprovado.' unless asset.kind == format
  end

  def validate_variables!(component, key)
    variables = component['text'].to_s.scan(/\{\{\s*([^{}]+?)\s*\}\}/).flatten.uniq
    data = processed.fetch(key, {})
    raise ArgumentError, "Parâmetros de #{key} devem ser um objeto." unless data.is_a?(Hash)
    raise ArgumentError, "Parâmetros de #{key} incompatíveis com o template." if (data.keys - variables).any?
    raise ArgumentError, "Preencha todas as variáveis de #{key}." unless variables.all? do |name|
      data[name].is_a?(String) && data[name].strip.present?
    end
  end

  def validate_buttons!(component)
    values = processed.fetch('buttons', [])
    raise ArgumentError, 'Parâmetros de botões devem ser uma lista.' unless values.is_a?(Array)

    buttons = Array(component['buttons'])
    raise ArgumentError, 'Índice de botão inválido.' if values.length > buttons.length

    buttons.each_with_index do |button, index|
      type = button['type'].to_s.upcase
      raise ArgumentError, "Botão não suportado: #{type}." unless SUPPORTED_BUTTONS.include?(type)

      value = values[index]
      dynamic = type == 'URL' && button['url'].to_s.include?('{{')
      if dynamic
        unless value.is_a?(Hash) && value['type'] == 'url' && value['parameter'].is_a?(String) && value['parameter'].strip.present?
          raise ArgumentError, "Preencha a variável do botão #{index + 1}."
        end
      elsif value.present?
        raise ArgumentError, 'Botão fixo não aceita parâmetros de envio.'
      end
    end
  end
end
