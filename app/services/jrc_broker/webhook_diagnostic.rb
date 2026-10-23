# Campaign admission evidence only. Never store exception messages, bodies, URLs or credentials.
class JrcBroker::WebhookDiagnostic
  KEY = 'jrc_broker_delivery'.freeze
  PHASES = %w[validate campaign_intent callback unknown].freeze
  OUTCOMES = %w[pending accepted rejected unknown].freeze
  REJECTION_STATUSES = [400, 401, 403, 404, 405, 409, 410, 413, 415, 422].freeze

  def initialize(message)
    @message = message
  end

  def read
    raw = @message&.content_attributes.to_h[KEY]
    return {} unless raw.is_a?(Hash) && raw['version'] == 1

    { 'version' => 1, 'phase' => PHASES.include?(raw['phase']) ? raw['phase'] : 'unknown',
      'outcome' => OUTCOMES.include?(raw['outcome']) ? raw['outcome'] : 'unknown',
      'error_class' => safe_class(raw['error_class']), 'http_status' => safe_status(raw['http_status']),
      'in_flight' => raw['in_flight'] == true, 'uncertain' => raw['uncertain'] == true, 'accepted' => raw['accepted'] == true }
  end

  def callback_started!
    update do |prior|
      raise JrcBroker::WebhookDelivery::ContextChanged if @message.failed?

      base.merge('phase' => 'callback', 'outcome' => 'pending', 'in_flight' => true,
                 'accepted' => prior['accepted'] == true, 'uncertain' => prior['uncertain'] == true || prior['in_flight'] == true)
    end
  end

  def callback_accepted!
    update { |_prior| base.merge('phase' => 'callback', 'outcome' => 'accepted', 'accepted' => true) }
  end

  def failure!(error, phase: nil)
    update { |prior| failure_result(error, phase, prior) }
  end

  def self.rejected?(proof)
    return false if proof.values_at('in_flight', 'uncertain', 'accepted').any?

    proof['version'] == 1 && proof['outcome'] == 'rejected' && proof['phase'] != 'unknown' &&
      (REJECTION_STATUSES.include?(proof['http_status']) || proof['error_class'] == 'JrcBroker::WebhookDelivery::ContextChanged')
  end

  private

  def failure_result(error, phase, prior)
    if error.is_a?(JrcBroker::WebhookDelivery::Unavailable) && phase.nil? && prior.present?
      return prior.merge('outcome' => 'unknown', 'uncertain' => true)
    end

    phase = 'unknown' unless PHASES.include?(phase)
    status = http_status(error)
    rejected = error.is_a?(JrcBroker::WebhookDelivery::ContextChanged) || REJECTION_STATUSES.include?(status)
    uncertain = callback_uncertain?(prior, phase, rejected)
    base.merge('phase' => phase, 'outcome' => failure_outcome(prior, phase, rejected, uncertain),
               'error_class' => safe_class(error.class.name), 'http_status' => status,
               'accepted' => prior['accepted'] == true, 'uncertain' => uncertain)
  end

  def callback_uncertain?(prior, phase, rejected)
    prior['uncertain'] == true || (phase != 'callback' && prior['in_flight'] == true) || (phase == 'callback' && !rejected)
  end

  def failure_outcome(prior, phase, rejected, uncertain)
    rejected && !uncertain && prior['accepted'] != true && phase != 'unknown' ? 'rejected' : 'unknown'
  end

  def update
    return unless @message&.additional_attributes.to_h&.dig('jrc_campaign_broker') == true

    @message.with_lock do
      next unless @message.additional_attributes.to_h['jrc_campaign_broker'] == true

      result = yield read
      # Correlation/diagnostics must not emit another message_updated callback.
      @message.update_columns(content_attributes: @message.content_attributes.to_h.merge(KEY => result)) # rubocop:disable Rails/SkipsModelValidations
      result
    end
  end

  def base
    { 'version' => 1, 'in_flight' => false, 'uncertain' => false, 'accepted' => false }
  end

  def safe_class(value)
    value if value.is_a?(String) && value.length <= 150 && /\A[A-Z][A-Za-z0-9_]*(?:::[A-Z][A-Za-z0-9_]*)*\z/.match?(value)
  end

  def safe_status(value)
    value if value.is_a?(Integer) && value.between?(100, 599)
  end

  def http_status(error)
    return safe_status(error.status) if error.is_a?(JrcBroker::Client::Error)
    return unless error.is_a?(SafeFetch::HttpError)

    safe_status(error.message.to_s[/\A([1-5]\d{2})\b/, 1]&.to_i)
  end
end
