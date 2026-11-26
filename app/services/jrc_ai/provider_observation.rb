# Only metadata returned by the authenticated runtime belongs here.
class JrcAi::ProviderObservation
  HEADERS = %w[x-ratelimit-limit-requests x-ratelimit-limit-tokens x-ratelimit-remaining-requests
               x-ratelimit-remaining-tokens x-ratelimit-reset-requests x-ratelimit-reset-tokens retry-after].freeze

  def self.record!(value, input:, provider:)
    return if value.nil?

    valid = value.is_a?(Hash) && value.keys.sort == %w[account_id headers http_status request_id] &&
            value['account_id'] == input['account_id'] && value['request_id'] == input['request_id'] &&
            value['http_status'].is_a?(Integer) && value['http_status'].between?(100, 599) &&
            value['headers'].is_a?(Hash) && (value['headers'].keys - HEADERS).empty? &&
            value['headers'].values.all? { |text| text.is_a?(String) && /\A[a-z0-9 .-]{1,80}\z/i.match?(text) }
    raise JrcNico::RuntimeClient::Error, 'invalid_scope' unless valid && provider && provider.account_id == input['account_id']

    model = input.dig('provider', 'model') || provider.default_model
    provider.with_lock do
      provider.update!(settings: provider.settings.merge('provider_observation' => {
        'http_status' => value['http_status'], 'headers' => value['headers'],
        'observed_at' => Time.current.iso8601(6), 'model' => model,
        'source' => 'provider_response', 'balance_available' => false
      }))
    end
  end
end
