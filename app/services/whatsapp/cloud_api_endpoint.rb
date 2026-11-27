require 'uri'

class Whatsapp::CloudApiEndpoint
  def self.base_url
    uri = URI.parse(ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com'))
    unless uri.is_a?(URI::HTTPS) && uri.host == 'graph.facebook.com' && uri.port == 443 &&
           uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil? && uri.path.in?(['', '/'])
      raise ArgumentError, 'A caixa whatsapp_cloud exige a API oficial graph.facebook.com. Nenhum conector alternativo será utilizado.'
    end

    'https://graph.facebook.com'
  rescue URI::InvalidURIError
    raise ArgumentError, 'Endereço da API oficial Meta inválido. Nenhum conector alternativo será utilizado.'
  end
end
