# frozen_string_literal: true

class JrcContactCenter::QueueCalendarRemovals
  INPUT = %w[unit_id queue_id expected_revision binding_id idempotency_key reviewed].freeze
  RESULT = %w[format account_id unit_id queue_id idempotency_key removed_binding_id removed_calendar_digest
              queue_revision_after historical_receipt local_only pabx_confirmed external_impact].freeze

  def initialize(context:, unit_id:)
    raise ArgumentError unless unit_id.is_a?(String) || unit_id.is_a?(Integer)

    @context = context.slice(:account, :account_user, :user)
    @unit_id = JrcServiceDesk::Input.id(unit_id)
    refresh!
  rescue ArgumentError
    raise JrcContactCenter::OperationError, 'invalid_queue_calendar_removal'
  end

  def call(input)
    validate_input!(input)
    JrcContactCenter::AuthorityTransaction.call(account: @context.fetch(:account), member: @context.fetch(:account_user)) do
      refresh!
      queue = @access.queues.where(unit_id: @unit_id).lock.find(input.fetch('queue_id'))
      before = prior_receipt(queue, input)
      before || remove!(queue, input)
    end
  end

  private

  def refresh!
    @context.each_value(&:reload)
    raise Pundit::NotAuthorizedError unless @context.fetch(:account).active? && @context.fetch(:user).active_for_authentication?

    @access = JrcContactCenter::AccessScope.new(user_context: @context)
    raise Pundit::NotAuthorizedError unless @access.policy.configure?

    @access.units.find(@unit_id)
  end

  def validate_input!(input)
    invalid! unless input_shape?(input)
    invalid! unless identifier?(input.fetch('queue_id'))
    invalid! unless input.fetch('unit_id') == @unit_id.to_s && input.fetch('reviewed') == true
    invalid! unless %w[binding_id idempotency_key].all? { |key| uuid?(input.fetch(key)) }
    invalid! unless input.fetch('expected_revision').is_a?(String) && input.fetch('expected_revision').match?(/\A[a-f0-9]{64}\z/)
  end

  def input_shape?(input)
    input.is_a?(Hash) && input.keys.all?(String) && input.keys.sort == INPUT.sort
  end

  def identifier?(value)
    value.is_a?(String) && JrcServiceDesk::Input.id(value).to_s == value
  rescue ArgumentError
    false
  end

  def uuid?(value)
    value.is_a?(String) && JrcContactCenter::CalendarCatalogState::UUID.match?(value)
  end

  def invalid!
    raise JrcContactCenter::OperationError, 'invalid_queue_calendar_removal'
  end

  def conflict!
    raise JrcContactCenter::OperationError.new('queue_calendar_removal_conflict', status: :conflict)
  end

  def prior_receipt(queue, input)
    records = Audited.audit_class.where(auditable: queue, associated: @context.fetch(:account),
                                       comment: JrcContactCenter::ConfigurationAudit::COMMENT, action: 'update')
    records = records.where("audited_changes -> 'queue_calendar_removal' ->> 'idempotency_key' = ?", input.fetch('idempotency_key'))
    rows = records.limit(2).to_a
    conflict! if rows.length > 1
    return if rows.empty?

    audit = rows.sole
    conflict! unless audit.user == @context.fetch(:user)
    receipt = audit.audited_changes.fetch('queue_calendar_removal')
    verify_receipt!(queue, input, receipt)
    receipt.fetch('result').merge('audit_id' => audit.id.to_s)
  end

  def verify_receipt!(queue, input, receipt)
    shape = receipt.is_a?(Hash) && receipt.keys.all?(String) &&
            receipt.keys.sort == (JrcContactCenter::QueueCalendarRemovalAudit::FIELDS + ['result']).sort
    conflict! unless shape && receipt['format'] == JrcContactCenter::QueueCalendarRemovalAudit::FORMAT
    scope = JrcContactCenter::ConfigurationAuditSnapshot.capture(queue).fetch('scope')
    valid = receipt.fetch('request_digest') == JrcContactCenter::ConfigurationRevision.content_token(input) &&
            receipt.fetch('actor_user_id') == @context.fetch(:user).id.to_s && receipt.fetch('scope_snapshot') == scope
    conflict! unless valid
    verify_result!(queue, input, receipt)
  end

  def verify_result!(queue, input, receipt)
    result = receipt.fetch('result')
    conflict! unless result.is_a?(Hash) && result.keys.all?(String) && result.keys.sort == RESULT.sort
    expected = { 'format' => JrcContactCenter::QueueCalendarRemovalAudit::FORMAT, 'account_id' => queue.account_id.to_s,
                 'unit_id' => @unit_id.to_s, 'queue_id' => queue.id.to_s, 'idempotency_key' => input.fetch('idempotency_key'),
                 'removed_binding_id' => input.fetch('binding_id'), 'removed_calendar_digest' => receipt.fetch('calendar_digest'),
                 'historical_receipt' => true, 'local_only' => true, 'pabx_confirmed' => false, 'external_impact' => 'unknown' }
    conflict! unless result.except('queue_revision_after') == expected
    token = result.fetch('queue_revision_after')
    conflict! unless token.is_a?(String) && token.match?(/\A[a-f0-9]{64}\z/)
  end

  def remove!(queue, input)
    current = JrcContactCenter::QueueCalendarState.new(queue: queue).call
    conflict! unless current && current.fetch('id') == input.fetch('binding_id')
    JrcContactCenter::ConfigurationRevision.check!(queue, input.fetch('expected_revision'))
    queue.cc_calendar_removal_review = review(queue, input, current)
    queue.update!(settings: queue.settings.except(JrcContactCenter::QueueCalendarState::KEY))
    prior_receipt(queue.reload, input) || raise(JrcContactCenter::OperationError, 'queue_calendar_removal_receipt_missing')
  ensure
    queue.cc_calendar_removal_review = nil
  end

  def review(queue, input, current)
    { 'format' => 'jrc-cc-queue-calendar-removal-v1', 'idempotency_key' => input.fetch('idempotency_key'),
      'request_digest' => JrcContactCenter::ConfigurationRevision.content_token(input), 'reviewed' => true,
      'actor_user_id' => @context.fetch(:user).id.to_s,
      'scope_snapshot' => JrcContactCenter::ConfigurationAuditSnapshot.capture(queue).fetch('scope'),
      'binding_id' => current.fetch('id'), 'calendar_id' => current.fetch('calendar_snapshot').fetch('id'),
      'calendar_digest' => current.fetch('calendar_digest') }
  end
end
