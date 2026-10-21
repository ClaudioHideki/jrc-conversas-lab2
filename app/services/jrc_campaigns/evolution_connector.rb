require 'uri'

# Only server-side configuration can opt an API inbox into campaign delivery.
class JrcCampaigns::EvolutionConnector
  ENV_KEY = 'JRC_CAMPAIGNS_EVOLUTION_CONNECTORS'.freeze
  attr_reader :inbox, :settings

  def self.for(inbox)
    return unless inbox&.channel_type == 'Channel::Api'

    configurations = JSON.parse(ENV.fetch(ENV_KEY, '[]'))
    raise ArgumentError, "#{ENV_KEY} deve ser uma lista." unless configurations.is_a?(Array)

    raise ArgumentError, 'Cada conector Evolution deve ser um objeto.' unless configurations.all? { |item| item.is_a?(Hash) }

    matches = configurations.select { |item| item['account_id'] == inbox.account_id && item['inbox_id'] == inbox.id }
    raise ArgumentError, 'Conector Evolution duplicado.' if matches.size > 1
    return if matches.empty?

    new(inbox, matches.first).tap(&:validate!)
  end

  def initialize(inbox, settings)
    @inbox = inbox
    @settings = settings
  end

  def validate!
    uri = URI.parse(base_url)
    unless uri.scheme == 'https' && uri.host.present? && uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && uri.path.in?(['', '/'])
      raise ArgumentError, 'URL HTTPS da Evolution inválida.'
    end
    raise ArgumentError, 'Instância Evolution inválida.' unless instance.match?(/\A[A-Za-z0-9_-]{1,100}\z/)
    raise ArgumentError, 'Número remetente Evolution inválido.' unless sender_number.match?(/\A[1-9]\d{7,14}\z/)
    unless settings['api_key_env'].to_s.match?(/\AJRC_CAMPAIGNS_EVOLUTION_[A-Z0-9_]+_API_KEY\z/)
      raise ArgumentError, 'Nome da variável de credencial Evolution inválido.'
    end
    unless inbox.channel.webhook_url == "#{base_url}/chatwoot/webhook/#{instance}"
      raise ArgumentError, 'O webhook da caixa não corresponde à instância Evolution configurada.'
    end
    raise ArgumentError, 'Intervalo Evolution deve ser de pelo menos 60 segundos.' if min_interval_seconds < 60
    raise ArgumentError, 'Limite diário Evolution deve estar entre 1 e 100.' unless daily_limit.between?(1, 100)
  rescue URI::InvalidURIError
    raise ArgumentError, 'URL HTTPS da Evolution inválida.'
  end

  def base_url
    settings.fetch('base_url').to_s.delete_suffix('/')
  end

  def instance
    settings.fetch('instance').to_s
  end

  def sender_number
    settings.fetch('sender_number').to_s
  end

  def min_interval_seconds
    Integer(settings.fetch('min_interval_seconds', 60))
  end

  def daily_limit
    Integer(settings.fetch('daily_limit', 50))
  end

  def api_key
    ENV.fetch(settings.fetch('api_key_env')).presence || raise(ArgumentError, 'Credencial Evolution ausente.')
  end

  def public_configuration
    settings.slice('account_id', 'inbox_id', 'base_url', 'instance', 'sender_number', 'min_interval_seconds', 'daily_limit')
  end
end
