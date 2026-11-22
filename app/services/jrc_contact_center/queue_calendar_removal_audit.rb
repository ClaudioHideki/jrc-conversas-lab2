# frozen_string_literal: true

class JrcContactCenter::QueueCalendarRemovalAudit
  FORMAT = 'jrc-cc-queue-calendar-removal-v1'
  FIELDS = %w[format idempotency_key request_digest reviewed actor_user_id scope_snapshot binding_id calendar_id calendar_digest].freeze

  def self.validate_model_intent!(record, previous)
    old = JrcContactCenter::QueueCalendarState.new(queue: record).validate!(previous)
    scope = JrcContactCenter::ConfigurationAuditSnapshot.capture(record).fetch('scope')
    validate!(record, record.cc_calendar_removal_review, old, scope)
  end

  def self.fields(record, before:)
    return {} unless record.is_a?(JrcContactCenter::Queue) && record.cc_calendar_removal_review

    review = record.cc_calendar_removal_review
    old = before.fetch('attributes').fetch('settings').fetch(JrcContactCenter::QueueCalendarState::KEY)
    validate!(record, review, old, before.fetch('scope'))
    result = receipt(record, review, old)
    record.cc_calendar_removal_review = nil
    { 'queue_calendar_removal' => review.deep_dup.merge('result' => result) }
  end

  def self.validate!(record, review, old, scope)
    invalid! unless header?(review)
    invalid! unless same_actor?(review)
    invalid! unless same_scope?(record, review, scope)
    invalid! unless same_source?(review, old)
    invalid! if record.settings.key?(JrcContactCenter::QueueCalendarState::KEY)
  end

  def self.header?(review)
    review.is_a?(Hash) && review.keys.all?(String) && review.keys.sort == FIELDS.sort && review['format'] == FORMAT &&
      review['reviewed'] == true && uuid?(review['idempotency_key']) && digest?(review['request_digest'])
  end

  def self.same_actor?(review)
    Current.user && review.fetch('actor_user_id') == Current.user.id.to_s
  end

  def self.same_scope?(record, review, scope)
    review.fetch('scope_snapshot') == scope && scope == JrcContactCenter::ConfigurationAuditSnapshot.capture(record).fetch('scope')
  end

  def self.same_source?(review, old)
    review.fetch('binding_id') == old.fetch('id') && review.fetch('calendar_id') == old.fetch('calendar_snapshot').fetch('id') &&
      review.fetch('calendar_digest') == old.fetch('calendar_digest')
  end

  def self.receipt(record, review, old)
    { 'format' => FORMAT, 'account_id' => record.account_id.to_s, 'unit_id' => record.unit_id.to_s, 'queue_id' => record.id.to_s,
      'idempotency_key' => review.fetch('idempotency_key'), 'removed_binding_id' => old.fetch('id'),
      'removed_calendar_digest' => old.fetch('calendar_digest'), 'queue_revision_after' => JrcContactCenter::ConfigurationRevision.token(record),
      'historical_receipt' => true, 'local_only' => true, 'pabx_confirmed' => false, 'external_impact' => 'unknown' }
  end

  def self.uuid?(value)
    value.is_a?(String) && JrcContactCenter::CalendarCatalogState::UUID.match?(value)
  end

  def self.digest?(value)
    value.is_a?(String) && value.match?(/\A[a-f0-9]{64}\z/)
  end

  def self.invalid!
    raise JrcContactCenter::OperationError, 'invalid_queue_calendar_removal_audit'
  end
  private_class_method :validate!, :receipt, :uuid?, :digest?, :invalid!, :header?, :same_actor?, :same_scope?, :same_source?
end
