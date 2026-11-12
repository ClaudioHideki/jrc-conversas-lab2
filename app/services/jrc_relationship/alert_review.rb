# Human assessment of a monitoring cause, independent from completion/customer feedback.
class JrcRelationship::AlertReview
  STATUSES = %w[pending confirmed false_positive].freeze

  def self.available?(metadata)
    metadata['automatic'] == true && metadata['automatic_cause_digest'].is_a?(String) &&
      metadata['automatic_cause_digest'].match?(/\A[a-f0-9]{64}\z/)
  end

  def self.projection(metadata, factors:, priority:)
    return { available: false } unless metadata.is_a?(Hash) && available?(metadata)

    review = metadata['alert_review']
    current = review.is_a?(Hash) && review.slice('cause_digest', 'factors', 'priority') == {
      'cause_digest' => metadata['automatic_cause_digest'], 'factors' => factors, 'priority' => priority
    }
    { available: true, status: 'pending', stale: review.present? && !current }.merge(
      current ? review.slice('status', 'note', 'actor_id', 'reviewed_at').symbolize_keys : {}
    )
  end

  def self.summary(scope)
    alerts = scope.where("metadata -> 'automatic' = 'true'::jsonb AND metadata ->> 'automatic_cause_digest' ~ '^[a-f0-9]{64}$'")
    current = alerts.where("metadata -> 'alert_review' ->> 'cause_digest' = metadata ->> 'automatic_cause_digest'")
                    .where("metadata -> 'alert_review' -> 'factors' = jrc_relationship_actions.factors")
                    .where("metadata -> 'alert_review' -> 'priority' = to_jsonb(jrc_relationship_actions.priority)")
    counts = current.group(Arel.sql("metadata -> 'alert_review' ->> 'status'")).count
    confirmed = counts.fetch('confirmed', 0)
    false_positive = counts.fetch('false_positive', 0)
    total = alerts.count
    reviewed = confirmed + false_positive
    { total: total, confirmed: confirmed, false_positive: false_positive, pending: total - reviewed, reviewed: reviewed,
      human_confirmation_percent: reviewed.positive? ? (confirmed.fdiv(reviewed) * 100).round(1) : nil }
  end

  def self.apply!(record, attributes, actor:)
    raise ArgumentError, 'Only automatic monitoring alerts can receive a human assessment' unless available?(record.metadata)

    previous = record.metadata['alert_review'] || {}
    value = validated_assessment(attributes).merge('cause_digest' => record.metadata.fetch('automatic_cause_digest'),
                                                   'factors' => record.factors.deep_dup, 'priority' => record.priority)
    return if previous.slice(*value.keys) == value

    record.metadata = record.metadata.merge('alert_review' => value.merge('actor_id' => actor.id, 'reviewed_at' => Time.current.iso8601(6)))
  end

  def self.validated_assessment(attributes)
    status, note = attributes.values_at('alert_review_status', 'alert_review_note')
    unless STATUSES.include?(status) && note.is_a?(String) && note.strip.present? && note.length <= 4000
      raise ArgumentError, 'Select a human assessment and provide a reason of at most 4000 characters'
    end

    { 'status' => status, 'note' => note.strip }
  end
  private_class_method :validated_assessment
end
