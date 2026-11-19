# frozen_string_literal: true

class JrcContactCenter::AgentStateHistoryPresenter
  def initialize(observed_at:)
    @observed_at = observed_at
  end

  # No raw metadata, reasons, justifications, form answers, commands or provider identifiers.
  def call(event)
    {
      id: event.id.to_s, account_user_id: event.account_user_id.to_s, agent_name: event.account_user.user.available_name,
      queue_id: event.queue_id&.to_s, queue_name: event.queue&.name, state: event.state,
      started_at: event.started_at.iso8601, ended_at: event.ended_at&.iso8601,
      duration_seconds: [[event.ended_at || @observed_at, @observed_at].min - event.started_at, 0].max.floor,
      source: event.source == JrcContactCenter::AgentStateManager::LOCAL_SOURCE ? 'local' : 'provider',
      provider_confirmed: event.metadata['provider_confirmed'] == true
    }
  end
end
