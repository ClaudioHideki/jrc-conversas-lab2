# frozen_string_literal: true

# Small Groq quotas need a bounded projection and time between workflow turns.
# This never changes the source records, authorization, tools or usage receipts.
class JrcNico::GroqContext
  def self.project(account:, message:, context:, history:)
    provider = JrcAi::AccountProvider.resolve(account)
    observation = provider.settings['provider_observation'] || {}
    headers = observation['headers'] || {}
    limit = Integer(headers['x-ratelimit-limit-tokens'], exception: false)
    small = URI.parse(provider.request_base_url).host == 'api.groq.com' &&
            observation['source'] == 'provider_response' && observation['model'] == provider.default_model && limit&.between?(1, 8000)
    return [context, history] unless small

    wait_for_window(account, provider, observation)
    projected = compact_knowledge(context.deep_stringify_keys)
    projected.delete('module_guides')
    last = projected['last_result']
    reads = Array(projected['tool_results'])
    projected.delete('last_result') if last && reads.any? { |row| row['tool'] == last['tool'] && row['result'] == last['result'] }
    recent = history.last(4).map(&:deep_dup)
    recent.pop if recent.last && recent.last['role'] == 'user' && recent.last['content'] == message
    projected['context_window'] = { 'history_omitted' => history.size - recent.size,
                                    'module_guides_omitted' => true, 'knowledge_characters_per_document' => 1000 }
    [projected, recent]
  end

  def self.compact_knowledge(value)
    return value.map { |item| compact_knowledge(item) } if value.is_a?(Array)
    return value unless value.is_a?(Hash)

    projected = value.transform_values { |item| compact_knowledge(item) }
    if value['resource_type'] == 'JrcNico::KnowledgeDocument' && value['body'].is_a?(String) && value['body'].length > 1000
      projected['body'] = value['body'].first(1000)
      projected['body_truncated'] = true
      projected['source_links'] = value['body'].scan(%r{https?://[^\s<>"']+}).map { |url| url.sub(/[),.;\]]+\z/, '') }.uniq.first(5)
    end
    projected
  end
  private_class_method :compact_knowledge

  def self.wait_for_window(account, provider, observation)
    headers = observation.fetch('headers')
    remaining = Integer(headers['x-ratelimit-remaining-tokens'], exception: false)
    receipt = account.jrc_ai_usage_events.where(provider_id: provider.id, model: provider.default_model, feature: 'nico_operator')
                     .where('metadata @> ?', { usage_estimated: false }.to_json).order(id: :desc).first
    return unless remaining && receipt && remaining < receipt.total_tokens

    reset = headers['x-ratelimit-reset-tokens'].to_s.match(/\A(?:(\d+)m)?(\d+(?:\.\d+)?)s\z/)
    return unless reset && observation['observed_at'].is_a?(String)

    observed = Time.iso8601(observation.fetch('observed_at'))
    return if observed > Time.current + 1.second

    seconds = observed + reset[1].to_i.minutes + reset[2].to_f - Time.current
    # The operator planner already runs outside request/DB locks. No inference
    # reservation is created until the provider's observed window has elapsed.
    Kernel.sleep([seconds, 60].min) if seconds.positive?
  end
  private_class_method :wait_for_window
end
