class JrcAi::CopilotProvider
  ERROR_CODES = {
    RubyLLM::UnauthorizedError => 'provider_unauthorized',
    RubyLLM::ForbiddenError => 'provider_forbidden',
    RubyLLM::RateLimitError => 'provider_rate_limited',
    RubyLLM::PaymentRequiredError => 'provider_quota_exceeded',
    RubyLLM::ModelNotFoundError => 'invalid_configuration',
    RubyLLM::ConfigurationError => 'invalid_configuration'
  }.freeze

  def self.error_response(error, account:, feature:)
    code = ERROR_CODES.find { |error_class, _| error.is_a?(error_class) }&.last || 'provider_unavailable'
    Rails.logger.warn("[LLM] account=#{account.id} feature=#{feature} code=#{code}")
    { error: JrcNico::RuntimeClient::Error.new(code).user_message, error_code: code }
  end

  def self.record_usage(response, credential:, account:, feature:)
    input_tokens = response.input_tokens || 0
    output_tokens = response.output_tokens || 0
    JrcAi::UsageEvent.create!(
      account: account, provider: credential[:provider], user: Current.user,
      agent_key: 'copilot', feature: feature, model: credential[:model],
      input_tokens: input_tokens, output_tokens: output_tokens,
      total_tokens: input_tokens + output_tokens, metadata: { cost_available: false }
    )
  end
end
