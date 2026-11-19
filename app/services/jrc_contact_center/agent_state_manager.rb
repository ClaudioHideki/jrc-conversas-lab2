# frozen_string_literal: true

require 'digest'

class JrcContactCenter::AgentStateManager
  OPERATOR_STATES = %w[offline available paused].freeze
  LOCAL_SOURCE = 'jrc_conversas'
  JUSTIFICATION_LIMIT = 1000
  NATIVE_PAUSES = {
    'lunch' => 'lunch_break', 'bathroom' => 'bathroom_break', 'meeting' => 'meeting',
    'training' => 'training', 'feedback' => 'feedback', 'end_shift' => 'end_shift'
  }.freeze

  def initialize(account:, account_user:)
    @account = account
    @member = account.account_users.find(account_user.id)
    @closed_sessions = []
  end

  def transition(state:, command_id:, expected_state_version:, **options)
    attributes = request_attributes(state, options)
    digest = Digest::SHA256.hexdigest(attributes.merge(expected_state_version: expected_state_version.to_s).to_json)
    JrcContactCenter::AuthorityTransaction.call(account: @account, member: @member) do
      event = @member.with_lock do
        authorize_operator!
        validate_request!(attributes, command_id)
        operator_event(attributes, command_id, expected_state_version, digest)
      end
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

  def request_attributes(state, options)
    options.assert_valid_keys(:queue_id, :reason_code, :justification)
    attributes = { state: state, queue_id: options[:queue_id].presence, reason_code: options[:reason_code].presence }
    value = options[:justification]
    valid = value.nil? || (value.is_a?(String) && value.length <= JUSTIFICATION_LIMIT)
    raise JrcContactCenter::OperationError, 'invalid_pause_justification' unless valid

    if value.present? && value.strip.present?
      raise JrcContactCenter::OperationError, 'invalid_pause_justification' unless state == 'paused'

      attributes[:justification] = value.strip
    end
    attributes
  end

  def authorize_operator!
    context = { account: @account, account_user: @member, user: @member.user }
    policy = JrcContactCenter::ModulePolicy.new(context, :contact_center)
    raise Pundit::NotAuthorizedError unless @member.user.reload.active_for_authentication? && policy.operate?
  end

  def events
    JrcContactCenter::AgentStateEvent.where(account: @account, account_user: @member)
  end

  def snapshot
    JrcContactCenter::AgentStateSnapshot.new(account_user: @member)
  end

  def validate_request!(attributes, command_id)
    JrcContactCenter::PauseCatalog.new(account: @account).enforced? # Validate storage before any state write or replay.
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
    validate_operator_state!(state, attributes, expected_version)
    previous = state.current
    values = attributes.except(:justification).merge(started_at: Time.current, source: LOCAL_SOURCE, external_event_id: event_id,
                                                     metadata: operator_metadata(attributes, digest))
    event = events.create!(values)
    close_previous(previous, event)
    sync_native_availability(attributes)
    event
  end

  def operator_metadata(attributes, digest)
    metadata = { 'request_digest' => digest, 'provider_confirmed' => false }
    return metadata unless attributes[:state] == 'paused'

    memberships = snapshot.memberships
    memberships = memberships.where(queue_id: attributes[:queue_id]) if attributes[:queue_id]
    catalog = JrcContactCenter::PauseCatalog.new(account: @account)
    definition = catalog.selection(attributes[:reason_code], member: @member, memberships: memberships)
    validate_pause_justification!(attributes, definition, catalog.enforced?)

    metadata['pause_justification'] = attributes[:justification] if attributes[:justification]
    definition ? metadata.merge('pause_definition' => definition) : metadata
  end

  def validate_pause_justification!(attributes, definition, enforced)
    raise JrcContactCenter::OperationError, 'pause_reason_not_allowed' if attributes[:justification] && !definition
    return unless enforced && definition&.fetch('justification_required', false) && attributes[:justification].blank?

    raise JrcContactCenter::OperationError, 'pause_justification_required'
  end

  def validate_operator_state!(state, attributes, expected_version)
    raise JrcContactCenter::OperationError.new('state_conflict', status: :conflict) unless state.version == expected_version.to_s

    blocked_by_acw = %w[available paused].include?(attributes[:state]) && pending_qualification?
    raise JrcContactCenter::OperationError.new('tabulation_pending', status: :conflict) if blocked_by_acw

    blocked = state.active_call? || %w[busy ringing in_call].include?(state.current&.state)
    raise JrcContactCenter::OperationError.new('call_active', status: :conflict) if blocked
  end

  def sync_native_availability(attributes)
    availability = case attributes[:state]
                   when 'available' then 'online'
                   when 'offline' then 'offline'
                   else NATIVE_PAUSES.fetch(attributes[:reason_code], 'busy')
                   end
    @member.update!(availability: availability)
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

    return if previous.ended_at || pending_acw?(previous)

    previous.update!(ended_at: event.started_at)
    session_id = previous.metadata['jrc_call_session_id']
    @closed_sessions << session_id if previous.state == 'acw' && session_id
  end

  def pending_acw?(event)
    event.state == 'acw' && pending_qualification?
  end

  def pending_qualification?
    JrcContactCenter::Qualification.pending.exists?(account: @account, account_user: @member)
  end

  def project_closed_sessions
    @closed_sessions.uniq.each { |id| JrcContactCenter::FactsProjector.new(account: @account).call(id) }
  end
end
