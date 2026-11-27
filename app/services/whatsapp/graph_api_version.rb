module Whatsapp::GraphApiVersion
  def self.current
    version = ENV.fetch('WHATSAPP_CLOUD_API_VERSION', 'v24.0')
    raise ArgumentError, 'Invalid WHATSAPP_CLOUD_API_VERSION' unless version.match?(/\Av\d+\.0\z/)

    version
  end
end
