# frozen_string_literal: true

# Fresh native scope after the same Account mutex used by configuration/authority mutations.
class JrcContactCenter::QueueCalendars
  INPUT = %w[unit_id queue_id calendar_id calendar_revision queue_revision idempotency_key reviewed].freeze

  def initialize(context:, unit_id:)
    @context = context.slice(:account, :account_user, :user)
    @unit_id = JrcServiceDesk::Input.id(unit_id)
    refresh!
  rescue ArgumentError
    raise JrcContactCenter::OperationError, 'invalid_queue_calendar_binding'
  end

  def targets(calendar_id, binding_filter: 'all')
    raise JrcContactCenter::OperationError, 'invalid_queue_calendar_binding' unless %w[all linked].include?(binding_filter)

    refresh!
    catalog.find!(calendar_id)
    relation = @access.queues.where(unit_id: @unit.id)
    return relation if binding_filter == 'all'

    relation.where("jrc_contact_center_queues.settings -> ? -> 'calendar_snapshot' ->> 'id' = ?",
                   JrcContactCenter::QueueCalendarState::KEY, calendar_id)
  end

  def show(queue_id)
    refresh!
    receipt(@access.queues.where(unit_id: @unit.id).find(queue_id))
  end

  def save!(input)
    validate_input!(input)
    JrcContactCenter::AuthorityTransaction.call(account: @context.fetch(:account), member: @context.fetch(:account_user)) do
      refresh!
      queue = @access.queues.where(unit_id: @unit.id).lock.find(input.fetch('queue_id'))
      write!(queue, input)
      receipt(queue.reload)
    end
  end

  private

  def refresh!
    @context.each_value(&:reload)
    raise Pundit::NotAuthorizedError unless @context.fetch(:account).active? && @context.fetch(:user).active_for_authentication?

    @access = JrcContactCenter::AccessScope.new(user_context: @context)
    raise Pundit::NotAuthorizedError unless @access.policy.configure?

    @unit = @access.units.find(@unit_id)
  end

  def catalog
    JrcContactCenter::CalendarCatalog.new(context: @context, unit_id: @unit_id)
  end

  def validate_input!(input)
    raise JrcContactCenter::OperationError, 'invalid_queue_calendar_binding' unless input_shape?(input)

    valid = input['reviewed'] == true && input['unit_id'] == @unit_id.to_s &&
            input['idempotency_key'].is_a?(String) && JrcContactCenter::CalendarCatalogState::UUID.match?(input['idempotency_key'])
    raise JrcContactCenter::OperationError, 'invalid_queue_calendar_binding' unless valid
  end

  def input_shape?(input)
    input.is_a?(Hash) && input.keys.all?(String) && input.keys.sort == INPUT.sort
  end

  def write!(queue, input)
    state = JrcContactCenter::QueueCalendarState.new(queue: queue)
    existing = state.call
    if existing && existing.fetch('id') == input.fetch('idempotency_key')
      check_replay!(existing, input)
      return
    end

    JrcContactCenter::ConfigurationRevision.check!(@unit, input.fetch('calendar_revision'))
    JrcContactCenter::ConfigurationRevision.check!(queue, input.fetch('queue_revision'))
    snapshot = catalog.find!(input.fetch('calendar_id'))
    binding = state.build(input, snapshot: snapshot)
    state.validate!(binding)
    queue.update!(settings: queue.settings.merge(JrcContactCenter::QueueCalendarState::KEY => binding))
  end

  def check_replay!(existing, input)
    return if existing.fetch('request_digest') == JrcContactCenter::ConfigurationRevision.content_token(input)

    raise JrcContactCenter::OperationError.new('queue_calendar_identity_conflict', status: :conflict)
  end

  def receipt(queue)
    binding = JrcContactCenter::QueueCalendarState.new(queue: queue).call
    current = binding && catalog.find!(binding.fetch('calendar_snapshot').fetch('id'))
    stale = binding && binding.fetch('calendar_digest') != JrcContactCenter::ConfigurationRevision.content_token(current)
    { 'queue_id' => queue.id.to_s, 'unit_id' => @unit.id.to_s, 'queue_name' => queue.name,
      'queue_revision' => JrcContactCenter::ConfigurationRevision.token(queue), 'binding' => binding,
      'calendar_changed' => stale == true, 'local_only' => true, 'pabx_confirmed' => false, 'external_impact' => 'unknown' }
  end
end
