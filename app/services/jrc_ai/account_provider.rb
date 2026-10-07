# frozen_string_literal: true

require 'uri'

# Credentials are resolved by the authenticated Account, never by browser/model input.
class JrcAi::AccountProvider
  def self.resolve(account)
    provider = account.jrc_ai_providers.enabled.preferred_first.find(&:api_key_configured?)
    raise JrcNico::RuntimeClient::Error, 'account_ai_not_configured' unless provider
    raise JrcNico::RuntimeClient::Error, 'provider_adapter_unavailable' unless compatible?(provider)
    raise JrcNico::RuntimeClient::Error, 'invalid_configuration' if provider.default_model.blank?

    raise JrcNico::RuntimeClient::Error, 'invalid_configuration' unless allowed_url?(provider.request_base_url)

    provider
  rescue URI::InvalidURIError
    raise JrcNico::RuntimeClient::Error, 'invalid_configuration'
  end

  def self.compatible?(provider)
    provider.openai_compatible? && provider.provider_type != 'azure_openai'
  end
  private_class_method :compatible?

  def self.allowed_url?(base_url)
    url = URI.parse(base_url)
    hosts = ENV.fetch('NICO_PROVIDER_ALLOWED_HOSTS', 'api.openai.com').split(',').map { |host| host.strip.downcase }
    url.is_a?(URI::HTTPS) && [url.userinfo, url.query, url.fragment].all?(&:nil?) &&
      url.port == 443 && hosts.include?(url.host.to_s.downcase)
  end
  private_class_method :allowed_url?

  def self.runtime_configuration(account, provider: nil)
    provider ||= resolve(account)
    raise JrcNico::RuntimeClient::Error, 'invalid_scope' unless provider.account_id == account.id

    { api_key: provider.api_key, model: provider.default_model, base_url: provider.request_base_url,
      transcription_model: provider.settings['transcription_model'].presence || 'gpt-4o-mini-transcribe' }
  end
end
