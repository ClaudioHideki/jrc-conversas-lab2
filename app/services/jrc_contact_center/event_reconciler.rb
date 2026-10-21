# frozen_string_literal: true

class JrcContactCenter::EventReconciler
  EVENT_HANDLERS = {
    'call.created' => :process_call_created,
    'call.answered' => :process_call_answered,
    'call.ended' => :process_call_ended,
    'ivr.menu.entered' => :process_ivr_event,
    'ivr.option.selected' => :process_ivr_event,
    'agent.state.changed' => :process_agent_state,
    'coe.fallback.triggered' => :process_fallback,
    'recording.available' => :process_recording
  }.merge(JrcContactCenter::CallJourney::EVENT_TYPES.excluding('call.created', 'call.answered', 'call.ended')
                                                  .index_with { :process_journey })
                   .merge('command.confirmed' => :process_command_confirmation, 'command.rejected' => :process_command_confirmation).freeze
  SUPPORTED_TYPES = EVENT_HANDLERS.keys.freeze

  def initialize(event_record:)
    @event_record = event_record
    @account = event_record.account
    @payload = event_record.payload.deep_stringify_keys
  end

  def call
    return @event_record if %w[processed ignored].include?(@event_record.status)

    @event_record.with_lock do
      next if %w[processed ignored].include?(@event_record.status)

      @event_record.attempts += 1
      if !@event_record.signature_verified?
        @event_record.update!(status: 'failed', last_error: 'signature_not_verified')
      elsif SUPPORTED_TYPES.include?(@event_record.event_type)
        reconcile_supported_event
      else
        @event_record.update!(status: 'ignored', processed_at: Time.current, last_error: nil)
      end
    end
    @event_record
  end

  private

  def reconcile_supported_event
    JrcContactCenter::ApplicationRecord.transaction(requires_new: true) do
      @account.with_lock { process_supported_event }
    end
    @event_record.update!(status: 'processed', processed_at: Time.current, last_error: nil)
  rescue StandardError => e
    @event_record.update!(status: 'failed', last_error: e.message.truncate(2000))
  end

  def process_supported_event
    raise JrcContactCenter::OperationError, 'unsupported_event_schema' unless @event_record.schema_version == '1.0'
    return if stale_answer?

    send(EVENT_HANDLERS.fetch(@event_record.event_type))
    process_journey if %w[call.created call.answered call.ended].include?(@event_record.event_type)
    project_session if @event_record.event_type.start_with?('call.', 'queue.', 'recording.', 'coe.')
  end

  def process_call_answered
    session = find_session!
    update_session('connected', answered_at: [session.answered_at, @event_record.occurred_at].compact.min)
  end

  def process_call_ended
    update_session('ended', ended_at: @event_record.occurred_at)
  end

  def process_call_created
    session = find_session || JrcContactCenter::CallSession.new(account: @account, correlation_id: correlation_id)
    session.assign_attributes(session_identity(session).merge(session_details(session)))
    session.save!
  end

  def session_identity(session)
    {
      provider: @event_record.provider,
      external_session_id: session.external_session_id.presence || @payload['call_session_id'],
      direction: session.direction.presence || value('direction', default: 'inbound'),
      status: session.persisted? ? session.status.presence || 'created' : 'created'
    }
  end

  def session_details(session)
    {
      ani: session.ani.presence || value('ani'),
      dnis: session.dnis.presence || value('dnis'),
      started_at: [session.started_at, @event_record.occurred_at].compact.min,
      metadata: session.metadata.to_h.merge(payload_body.except('jrc_f1'))
    }
  end

  def update_session(status, attributes)
    session = find_session!
    if %w[ended failed].include?(session.status)
      session.update!(safe_terminal_attributes(session, attributes))
      return
    end

    session.update!(attributes.merge(status: status))
  end

  def safe_terminal_attributes(session, attributes)
    attributes.each_with_object({}) do |(key, value), safe|
      next if key == :answered_at && session.ended_at && value > session.ended_at
      next if session.public_send(key).present?

      safe[key] = value
    end
  end

  def process_ivr_event
    session = find_session!
    session.ivr_events.create!(
      account: @account,
      external_event_id: @event_record.external_event_id,
      event_type: @event_record.event_type,
      menu_key: value('menu_key'),
      option_key: value('option_key'),
      occurred_at: @event_record.occurred_at,
      payload: payload_body
    )
  end

  def process_agent_state
    account_user = @account.account_users.find(value('account_user_id'))
    JrcContactCenter::AgentStateManager.new(account: @account, account_user: account_user).record_provider_event(
      state: value('state'), queue_id: value('queue_id'), reason_code: value('reason_code'), provider: @event_record.provider,
      occurred_at: @event_record.occurred_at, external_event_id: @event_record.external_event_id,
      metadata: payload_body.except('provider_confirmed', 'jrc_call_session_id')
    )
  end

  def process_journey
    JrcContactCenter::CallJourney.new(event_record: @event_record).call
  end

  def process_command_confirmation
    JrcContactCenter::CommandConfirmation.new(event_record: @event_record).call
  end

  def stale_answer?
    return false unless @event_record.event_type == 'call.answered'

    session = find_session!
    last = session.f1_data['state_at']
    %w[ended failed].exclude?(session.status) && last && @event_record.occurred_at < Time.iso8601(last)
  end

  def project_session
    session = find_session
    JrcContactCenter::FactsProjector.new(account: @account).call(session.id) if session
  end

  def process_fallback
    session = find_session!
    session.fallback_events.create!(
      account: @account,
      reason_code: value('reason_code', default: 'provider'),
      result: value('result', default: 'requested'),
      terminal: ActiveModel::Type::Boolean.new.cast(value('terminal', default: false)),
      occurred_at: @event_record.occurred_at,
      metadata: payload_body
    )
  end

  def process_recording
    session = find_session!
    JrcContactCenter::RecordingLink.find_or_create_by!(
      account: @account,
      provider: @event_record.provider,
      external_recording_id: value('recording_id')
    ) do |recording|
      recording.call_session = session
      recording.status = value('status', default: 'available')
      recording.duration_seconds = value('duration_seconds')
      recording.recorded_at = @event_record.occurred_at
      recording.metadata = payload_body.except('url', 'media_url', 'signed_url')
    end
  end

  def find_session
    session = JrcContactCenter::CallSession.find_by(account: @account, correlation_id: correlation_id)
    return session if session || @payload['call_session_id'].blank?

    JrcContactCenter::CallSession.find_by(account: @account, provider: @event_record.provider, external_session_id: @payload['call_session_id'])
  end

  def find_session!
    find_session || raise(ActiveRecord::RecordNotFound, 'contact center call session not found')
  end

  def correlation_id
    @payload['correlation_id'].presence || @payload['call_session_id'].presence || @event_record.external_event_id
  end

  def payload_body
    body = @payload['payload']
    body.is_a?(Hash) ? body.deep_stringify_keys : {}
  end

  def value(key, default: nil)
    @payload[key].presence || payload_body[key].presence || default
  end
end
