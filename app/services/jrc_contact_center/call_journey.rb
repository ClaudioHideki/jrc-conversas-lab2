# frozen_string_literal: true

class JrcContactCenter::CallJourney
  EVENT_TYPES = %w[call.created queue.entered call.offered call.answered call.held call.resumed call.transferred
                   call.leg.created call.leg.answered call.leg.ended call.abandoned call.ended].freeze
  HANDLERS = { 'call.created' => :created, 'queue.entered' => :queued, 'call.offered' => :offered,
               'call.answered' => :answered, 'call.held' => :held, 'call.resumed' => :resumed,
               'call.transferred' => :transferred, 'call.leg.created' => :created, 'call.leg.answered' => :answered,
               'call.leg.ended' => :leg_ended, 'call.abandoned' => :abandoned, 'call.ended' => :ended }.freeze

  def initialize(event_record:)
    @event = event_record
    @account = event_record.account
    body = event_record.payload['payload']
    @data = (body.is_a?(Hash) ? body : {}).merge(event_record.payload.except('payload'))
  end

  def call
    @session = find_session
    @session.with_lock do
      next unless applicable?

      @legs = JrcContactCenter::CallLegJourney.new(event_record: @event, session: @session)
      send(HANDLERS.fetch(@event.event_type))
      @session.update_f1_data('state_at' => @event.occurred_at.iso8601(6)) unless stale?
    end
  end

  private

  def applicable?
    terminal = %w[ended failed].include?(@session.status)
    backfill = terminal && @session.ended_at && %w[call.answered call.leg.answered call.ended].include?(@event.event_type) &&
               @event.occurred_at <= @session.ended_at
    backfill || (!terminal && !stale?)
  end

  def find_session
    correlation = @data['correlation_id'].presence || @data['call_session_id'].presence || @event.external_event_id
    scope = JrcContactCenter::CallSession.where(account: @account)
    session = scope.find_by(correlation_id: correlation)
    return session if session
    raise ActiveRecord::RecordNotFound if @data['call_session_id'].blank?

    scope.find_by!(provider: @event.provider, external_session_id: @data['call_session_id'])
  end

  def stale?
    last = @session.f1_data['state_at']
    last && @event.occurred_at < Time.iso8601(last)
  end

  def created
    @legs.apply('created')
  end

  def queued
    queue = JrcContactCenter::Queue.where(account: @account).find(@data.fetch('queue_id'))
    @session.update!(status: 'queued', current_queue: queue, current_unit: queue.unit)
    @session.update_f1_data('queue_entered_at' => @event.occurred_at.iso8601(6),
                            'entry_queued_at' => @session.f1_data['entry_queued_at'] || @event.occurred_at.iso8601(6),
                            'entry_queue_id' => @session.f1_data['entry_queue_id'] || queue.id)
  end

  def offered
    raise JrcContactCenter::OperationError, 'leg_id_required' if @data['leg_id'].blank?

    @session.update!(status: 'ringing')
    @session.update_f1_data('offered_at' => @session.f1_data['offered_at'] || @event.occurred_at.iso8601(6))
    leg = @legs.apply('ringing')
    agent_state(leg, 'ringing')
  end

  def answered
    unless %w[ended failed].include?(@session.status)
      @session.update!(status: 'connected', answered_at: [@session.answered_at, @event.occurred_at].compact.min)
    end
    leg = @legs.apply('connected')
    agent_state(leg, 'in_call') unless %w[ended failed].include?(@session.status)
  end

  def held
    @session.update!(status: 'held')
    @session.update_f1_data('hold_started_at' => @event.occurred_at.iso8601(6)) unless @session.f1_data['hold_started_at']
    @legs.apply('held')
  end

  def resumed
    close_hold
    @session.update!(status: 'connected')
    @legs.apply('connected')
  end

  def transferred
    leg = @legs.apply('transferred')
    agent_state(leg, leg&.answered_at ? 'acw' : 'unavailable')
    @session.update!(status: 'transferring')
    @session.update_f1_data('transferred' => true)
  end

  def leg_ended
    leg = @legs.apply('ended')
    agent_state(leg, leg&.answered_at ? 'acw' : 'unavailable')
  end

  def abandoned
    raise JrcContactCenter::OperationError, 'answered_call_cannot_abandon' if @session.answered_at

    @session.update!(status: 'ended', ended_at: @event.occurred_at)
    @session.update_f1_data('outcome' => 'abandoned')
    ended
  end

  def ended
    close_hold
    @session.legs.where.not(status: %w[ended transferred failed]).find_each do |leg|
      agent_state(leg, leg.answered_at ? 'acw' : 'unavailable')
    end
    @legs.close_all
  end

  def close_hold
    started = @session.f1_data['hold_started_at']
    return unless started

    seconds = [(@event.occurred_at - Time.iso8601(started)).to_i, 0].max
    @session.update_f1_data('hold_started_at' => nil, 'hold_seconds' => @session.f1_data.fetch('hold_seconds', 0) + seconds)
  end

  def agent_state(leg, state)
    return unless leg&.account_user
    return if state == 'acw' && JrcContactCenter::Qualification.exists?(account: @account, call_session: @session, account_user: leg.account_user)

    JrcContactCenter::AgentStateManager.new(account: @account, account_user: leg.account_user).record_provider_event(
      state: state, occurred_at: @event.occurred_at, external_event_id: "journey:#{@event.id}:#{leg.account_user_id}",
      queue_id: leg.queue_id, provider: @event.provider, derived: true, metadata: { 'jrc_call_session_id' => @session.id }
    )
  end
end
