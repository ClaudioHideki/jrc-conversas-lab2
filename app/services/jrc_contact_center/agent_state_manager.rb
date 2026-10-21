# frozen_string_literal: true

require 'digest'

class JrcContactCenter::AgentStateManager
  OPERATOR_STATES = %w[offline available paused].freeze
  LOCAL_SOURCE = 'jrc_conversas'

  def initialize(account:, account_user:)
    @account = account
    @member = account.account_users.find(account_user.id)
    @closed_sessions = []
  end

  def transition(state:, command_id:, expected_state_version:, queue_id: nil, reason_code: nil)
    attributes = { state: state, queue_id: queue_id.presence, reason_code: reason_code.presence }
    digest = Digest::SHA256.hexdigest(attributes.merge(expected_state_version: expected_state_version.to_s).to_json)
    validate_request!(attributes, command_id)
    @account.with_lock do
      event = @member.with_lock { operator_event(attributes, command_id, expected_state_version, digest) }
      project_closed_sessions
      event
    end
  rescue ActiveRecord::RecordNotUnique
    raise JrcContactCenter::OperationError.new('command_id_conflict', status: :conflict)
  end

  def record_provider_event(state:, occurred_at:, external_event_id:, provider:, **options)
    options.assert_valid_keys(:metadata, :queue_id, :reason_code, :derived)
    @account.with_lock do
      event = @member.with_lock do
        previous = snapshot.current
        event = events.create!(state: state, started_at: occurred_at, external_event_id: external_event_id,
                               source: provider, queue_id: options[:queue_id], reason_code: options[:reason_code],
                               metadata: options.fetch(:metadata, {}).merge('provider_confirmed' => !options.fetch(:derived, false)))
        close_previous(previous, event)
        event
      end
      project_closed_sessions
      event
    end
  end

  private

  def events
    JrcContactCenter::AgentStateEvent.where(account: @account, account_user: @member)
  end

  def snapshot
    JrcContactCenter::AgentStateSnapshot.new(account_user: @member)
  end

  def validate_request!(attributes, command_id)
    raise JrcContactCenter::OperationError, 'invalid_agent_state' unless OPERATOR_STATES.include?(attributes[:state])
    raise JrcContactCenter::OperationError, 'command_id_required' if command_id.blank? || command_id.to_s.length > 100
    raise JrcContactCenter::OperationError, 'pause_reason_required' if attributes[:state] == 'paused' && attributes[:reason_code].blank?
    return if attributes[:queue_id].blank?

    snapshot.memberships.find_by!(queue_id: attributes[:queue_id])
  end

  def operator_event(attributes, command_id, expected_version, digest)
    event_id = "operator:#{command_id}"
    existing = JrcContactCenter::AgentStateEvent.find_by(account: @account, external_event_id: event_id)
    return replay(existing, digest) if existing

    state = snapshot
    raise JrcContactCenter::OperationError.new('state_conflict', status: :conflict) unless state.version == expected_version.to_s

    previous = state.current
    if attributes[:state] == 'available' && JrcContactCenter::Qualification.pending.exists?(account: @account, account_user: @member)
      raise JrcContactCenter::OperationError.new('tabulation_pending', status: :conflict)
    end
    blocked = state.active_call? || %w[busy ringing in_call].include?(previous&.state)
    raise JrcContactCenter::OperationError.new('call_active', status: :conflict) if blocked

    event = events.create!(attributes.merge(started_at: Time.current, source: LOCAL_SOURCE, external_event_id: event_id,
                                            metadata: { 'request_digest' => digest, 'provider_confirmed' => false }))
    close_previous(previous, event)
    event
  end

  def replay(event, digest)
    matches = event.account_user_id == @member.id && event.metadata['request_digest'] == digest
    raise JrcContactCenter::OperationError.new('command_id_conflict', status: :conflict) unless matches

    event
  end

  def close_previous(previous, event)
    return unless previous

    if event.started_at < previous.started_at
      event.update!(ended_at: previous.started_at)
      return
    end

    return if previous.ended_at
    if previous.state == 'acw' && JrcContactCenter::Qualification.pending.exists?(account: @account, account_user: @member)
      return
    end

    previous.update!(ended_at: event.started_at)
    session_id = previous.metadata['jrc_call_session_id']
    @closed_sessions << session_id if previous.state == 'acw' && session_id
  end

  def project_closed_sessions
    @closed_sessions.uniq.each { |id| JrcContactCenter::FactsProjector.new(account: @account).call(id) }
  end
end
