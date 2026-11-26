# frozen_string_literal: true

# Contract 2 names its ledger explicitly: independent native sequences may use
# the same numeric ID. No private rule body, target text or raw error is exposed.
class JrcContactCenter::EndingActions::DestinationAttemptProjection
  def initialize(member:)
    @member = member
  end

  def call(attempt)
    raise ActiveRecord::RecordNotFound unless attempt.account_id == @member.account_id

    capabilities = JrcContactCenter::EndingActions::DestinationOperationAvailability.new(
      account: @member.account, member: @member, attempt: attempt
    ).call
    identity(attempt).merge(terminal_fields(attempt.outcome)).merge(review_fields(attempt, capabilities)).merge(capabilities)
  end

  def legacy(attempt)
    JrcContactCenter::EndingActions::AttemptProjection.new(member: @member).call(attempt).merge(
      id: "legacy:#{attempt.id}", ledger: 'legacy', attempt_id: attempt.id.to_s, operation: 'create_task'
    )
  end

  private

  def identity(attempt)
    { id: "typed:#{attempt.id}", ledger: 'typed', attempt_id: attempt.id.to_s,
      origin_id: attempt.origin_id.to_s, rule_code: attempt.rule_code, version_id: attempt.version_id.to_s,
      destination_kind: attempt.destination_kind, operation: attempt.operation,
      request_id: attempt.request_key, queued_at: attempt.created_at.iso8601, can_reprocess_pending: false }
  end

  def terminal_fields(outcome)
    execution = outcome&.execution
    { outcome: outcome&.outcome || 'pending', result_code: outcome&.result_code,
      finished_at: outcome&.created_at&.iso8601, execution_id: execution&.id&.to_s,
      target: JrcContactCenter::EndingActions::DestinationTargetReference.new(member: @member).call(execution) }
  end

  def review_fields(attempt, capabilities)
    reviewable = capabilities.values.any?(true)
    { readiness_id: reviewable ? attempt.readiness_id.to_s : nil, rule_sha256: reviewable ? attempt.rule_sha256 : nil }
  end
end
