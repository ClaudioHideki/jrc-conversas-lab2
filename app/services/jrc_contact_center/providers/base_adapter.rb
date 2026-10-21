# frozen_string_literal: true

class JrcContactCenter::Providers::BaseAdapter
  class CapabilityUnavailable < StandardError; end

  CAPABILITIES = %w[
    sip_webrtc
    acd_queues
    ivr
    ddd_routing
    fallback
    agent_states
    cdr
    recordings
    originate
    hold
    transfer_blind
    transfer_attended
    callback
    signed_events
    high_availability
  ].freeze

  attr_reader :account

  def initialize(account:)
    @account = account
  end

  def provider_key
    raise NotImplementedError
  end

  def capabilities
    CAPABILITIES.index_with { 'pending_contract' }
  end

  def dispatch(_command)
    raise CapabilityUnavailable, 'JRC PABX command contract has not been homologated'
  end
end
