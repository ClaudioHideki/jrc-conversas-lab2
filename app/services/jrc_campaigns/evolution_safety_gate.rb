class JrcCampaigns::EvolutionSafetyGate
  class Halted < StandardError; end
  class Throttled < StandardError
    attr_reader :retry_at

    def initialize(retry_at)
      @retry_at = retry_at
      super('Aguardando intervalo operacional da Evolution.')
    end
  end

  def initialize(connector)
    @connector = connector
  end

  def reserve!
    channel.with_lock do
      state = channel.additional_attributes.to_h.fetch('jrc_campaign_evolution_state', {})
      raise Halted, state['halted_reason'] if state['halted_reason'].present?

      attempts = state['date'] == Date.current.iso8601 ? state['attempts'].to_i : 0
      raise Halted, 'Limite diário de tentativas Evolution atingido.' if attempts >= connector.daily_limit

      retry_at = Time.zone.parse(state['last_attempt_at']) + connector.min_interval_seconds.seconds if state['last_attempt_at']
      raise Throttled, retry_at if retry_at&.future?
      raise Halted, 'Tentativa Evolution anterior sem resultado persistido; revisar antes de retomar.' if state['inflight']

      save_state(state.merge('date' => Date.current.iso8601, 'attempts' => attempts + 1, 'last_attempt_at' => Time.current.iso8601, 'inflight' => true))
    end
  end

  def complete!
    channel.with_lock do
      state = channel.additional_attributes.to_h.fetch('jrc_campaign_evolution_state', {})
      save_state(state.merge('inflight' => false))
    end
  end

  def halt!(reason)
    channel.with_lock do
      state = channel.additional_attributes.to_h.fetch('jrc_campaign_evolution_state', {})
      save_state(state.merge('halted_reason' => reason, 'halted_at' => Time.current.iso8601))
    end
  end

  private

  attr_reader :connector

  def channel
    connector.inbox.channel
  end

  def save_state(state)
    channel.update!(additional_attributes: channel.additional_attributes.to_h.merge('jrc_campaign_evolution_state' => state))
  end
end
