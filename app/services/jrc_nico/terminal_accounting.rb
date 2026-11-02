# Only the authenticated runtime can issue complete terminal accounting evidence.
class JrcNico::TerminalAccounting
  OUTPUT_ERRORS = %w[provider_outer_json_invalid tool_arguments_invalid provider_schema_invalid].freeze
  KEYS = %w[version complete attempts request_id account_id mode model usage].freeze

  def self.receipt!(body, request)
    receipt = body['accounting']
    valid = ENV.fetch('NICO_MODE', nil) == 'provider' && body.keys.sort == %w[accounting error] && OUTPUT_ERRORS.include?(body['error'])
    valid &&= shape?(receipt) && scope?(receipt, request)
    raise JrcNico::RuntimeClient::Error, 'provider_usage_invalid' unless valid

    receipt
  end

  def self.shape?(receipt)
    return false unless receipt.is_a?(Hash)

    keys = receipt.keys.sort
    return false unless [KEYS.sort, (KEYS + ['usage_estimated']).sort].include?(keys)
    return false if receipt.key?('usage_estimated') && receipt['usage_estimated'] != true

    complete?(receipt)
  end

  def self.complete?(receipt)
    receipt['version'].is_a?(Integer) && receipt['version'] == 1 && receipt['complete'] == true &&
      receipt['attempts'].is_a?(Integer) && receipt['attempts'].between?(1, 2)
  end

  def self.scope?(receipt, request)
    receipt['account_id'].is_a?(Integer) && receipt['account_id'] == request['account_id'] &&
      receipt['request_id'] == request['request_id'] && receipt['mode'] == 'provider' &&
      receipt['model'].is_a?(String) && receipt['model'].length.between?(1, 150) && receipt['model'] == request.dig('provider', 'model')
  end

  private_class_method :shape?, :complete?, :scope?
end
