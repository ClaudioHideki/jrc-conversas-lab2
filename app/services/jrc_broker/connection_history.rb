class JrcBroker::ConnectionHistory
  def initialize(binding, user: nil, source_ip: nil)
    @binding = binding
    @user = user
    @source_ip = source_ip
  end

  def request!(kind, key:, state: {})
    @binding.with_lock do
      context = @binding.connection_state
      event_type = request_type(kind, state)
      write!(event_type, key: "#{event_type}:#{key}", actor_id: @user.id, correlation_id: key,
                         before: state['instanceStatus'], metadata: { 'result' => 'REQUESTED', 'source_ip' => @source_ip })
      attempt = {
        'kind' => event_type, 'key' => key, 'actor_id' => @user.id, 'status_before' => state['instanceStatus']
      }
      @binding.update!(connection_state: context.merge('attempt' => attempt))
    end
  end

  def result!(result, key: nil)
    @binding.with_lock do
      context = @binding.connection_state
      attempt = context['attempt']
      next unless attempt && matching_attempt?(attempt, result, key)

      attempt = attempt.merge('operation_id' => result['operationId'], 'expires_at' => result.dig('action', 'expiresAt'))
      @binding.update!(connection_state: context.merge('attempt' => attempt))
    end
  end

  def observe!(health)
    health = safe_health(health)
    @binding.with_lock do
      JrcBroker::Response.health(health, @binding) # Binding may have changed while the HTTP request was in flight.
      context = @binding.connection_state
      previous = context.fetch('health', {})
      previous = {} unless JrcBroker::OriginSnapshot.matching_scope?(@binding, previous)
      next if older_observation?(previous, health)

      attempt = context.fetch('attempt', {})
      observed = health.slice('integrationId', 'instanceId', 'inboxId', 'instanceStatus', 'integrationStatus', 'identityApproved', 'identityStatus',
                              'identityRevision', 'lastError', 'checkedAt')
      observed['checkedAt'] = previous['checkedAt'] if health['checkedAt'].nil? && observation_time(previous['checkedAt'])
      transition = transition_type(previous, health, attempt)
      record_transition!(transition, previous, health, attempt) if transition
      record_identity_change!(previous, health, attempt)
      record_expiry!(attempt) unless %w[CONNECTED RECONNECTED].include?(transition)
      context = context.except('attempt') if %w[CONNECTED RECONNECTED DISCONNECTED].include?(transition)
      origin = JrcBroker::OriginSnapshot.capture(@binding, health, previous: context['origin'])
      updated = context.merge('health' => observed, 'origin' => origin)
      @binding.update!(connection_state: updated) unless @binding.connection_state == updated
    end
  end

  def failed!(error, key:)
    code = error.message.to_s
    code = 'JRC_BROKER_UNAVAILABLE' unless /\A[A-Z][A-Z0-9_]{0,127}\z/.match?(code)
    write!('SESSION_FAILED', key: "FAILURE:#{key}", actor_id: @user&.id, correlation_id: key,
                             metadata: { 'result' => 'FAILED', 'error_code' => code })
  end

  def identity_confirmed!(key:)
    write!('IDENTITY_CONFIRMED', key: "IDENTITY:#{key}", actor_id: @user.id, correlation_id: key,
                                 metadata: { 'result' => 'APPROVED', 'source_ip' => @source_ip })
  end

  private

  def matching_attempt?(attempt, result, key)
    return attempt['key'] == key unless key.nil?

    result['operationId'].present? && attempt['operation_id'] == result['operationId']
  end

  def older_observation?(previous, health)
    previous_revision = previous['identityRevision']
    current_revision = health['identityRevision']
    return true if previous_revision.is_a?(Integer) && current_revision.is_a?(Integer) && current_revision < previous_revision

    previous_time = observation_time(previous['checkedAt'])
    current_time = observation_time(health['checkedAt'])
    previous_time && current_time && current_time < previous_time
  end

  def observation_time(value)
    Time.iso8601(value) if value.is_a?(String)
  rescue ArgumentError
    nil
  end

  def safe_health(health)
    unless health['checkedAt'].nil? || observation_time(health['checkedAt'])
      raise JrcBroker::Client::Error, 'JRC_BROKER_INVALID_RESPONSE'
    end
    error = health['lastError']
    error = 'SESSION_FAILED' if error.present? && !/\A[A-Z][A-Z0-9_]{0,127}\z/.match?(error.to_s)
    health.merge('lastError' => error)
  end

  def request_type(kind, state)
    return 'DISCONNECT_REQUESTED' unless kind == 'pair'

    state['identityApproved'] ? 'RECONNECT_REQUESTED' : 'CONNECT_REQUESTED'
  end

  def record_transition!(type, previous, health, attempt)
    metadata = { 'result' => 'OBSERVED' }
    metadata['error_code'] = health['lastError'].presence || 'SESSION_FAILED' if type == 'SESSION_FAILED'
    write!(type, actor_id: attempt['actor_id'], correlation_id: attempt['operation_id'] || attempt['key'],
                 before: previous['instanceStatus'], after: health['instanceStatus'], metadata: metadata)
  end

  def record_identity_change!(previous, health, attempt)
    return unless health['identityStatus'] == 'CONFIRMATION_REQUIRED'
    return if previous.values_at('identityStatus', 'identityRevision') == health.values_at('identityStatus', 'identityRevision')

    write!('NUMBER_MISMATCH', actor_id: attempt['actor_id'], metadata: { 'result' => 'BLOCKED' })
  end

  def connected?(state)
    state['instanceStatus'] == 'CONNECTED' && state['integrationStatus'] == 'READY' &&
      state['identityApproved'] && state['identityStatus'] == 'CONFIRMED'
  end

  def transition_type(previous, health, attempt)
    return connected_transition(previous, attempt) if connected?(health)
    return if previous.values_at('instanceStatus', 'lastError') == health.values_at('instanceStatus', 'lastError')

    case health['instanceStatus']
    when 'DISCONNECTED' then disconnected_transition(previous, attempt)
    when 'ERROR', 'PROVISIONING_FAILED' then 'SESSION_FAILED'
    end
  end

  def connected_transition(previous, attempt)
    return if connected?(previous)

    attempt['kind'] == 'RECONNECT_REQUESTED' ? 'RECONNECTED' : 'CONNECTED'
  end

  def disconnected_transition(previous, attempt)
    'DISCONNECTED' if previous['instanceStatus'].present? || attempt['kind'] == 'DISCONNECT_REQUESTED'
  end

  def record_expiry!(attempt)
    return if attempt['expires_at'].blank? || Time.iso8601(attempt['expires_at']) > Time.current

    write!('QR_EXPIRED', key: "QR_EXPIRED:#{attempt['operation_id'] || attempt['key']}", actor_id: attempt['actor_id'],
                         occurred_at: Time.iso8601(attempt['expires_at']), correlation_id: attempt['operation_id'] || attempt['key'],
                         metadata: { 'result' => 'EXPIRED' })
  end

  def write!(type, key: nil, **details)
    attributes = { account_id: @binding.account_id, inbox_id: @binding.inbox_id, event_type: type, event_key: key,
                   user_id: details.delete(:actor_id), status_before: details.delete(:before), status_after: details.delete(:after),
                   occurred_at: Time.current, metadata: {} }.merge(details)
    scope = JrcBrokerConnectionEvent.where(account_id: @binding.account_id, inbox_id: @binding.inbox_id)
    key ? scope.create_or_find_by!(event_key: key) { |event| event.assign_attributes(attributes) } : scope.create!(attributes)
  end
end
