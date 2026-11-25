# frozen_string_literal: true

# Internal technical writer, following RecordAttempt's existing v1 boundary.
# Its caller must own the account transaction and current original-agent
# authorization. This does not authorize a native target or execute an effect.
# Database guards derive all provenance; replay cannot replace reviewed consent
# or silently select a different failed predecessor.
class JrcContactCenter::EndingActions::RecordDestinationAttempt
  def initialize(account:, origin:, readiness:, rule_code:, destination_kind:)
    @account = account
    @origin = origin
    @readiness = readiness
    @code = rule_code
    @kind = destination_kind
  end

  def call(request_key:, consent: nil, retry_of: nil, reviewer: nil)
    raise JrcContactCenter::OperationError, 'ending_destination_requires_transaction' unless Account.connection.transaction_open?

    attributes = { origin: @origin, readiness: @readiness, rule_code: @code, destination_kind: @kind,
                   request_key: request_key, consent: consent, retry_of: retry_of,
                   retry_requested_by_account_user_id: reviewer&.id }
    scope = JrcContactCenter::EndingDestinationAttempt.where(account: @account)
    previous = scope.find_by(request_key: request_key)
    return replay!(previous, consent, retry_of, reviewer) if previous

    scope.create!(attributes).reload
  end

  private

  def replay!(previous, consent, retry_of, reviewer)
    expected = [@origin.id, @readiness.id, @code, @kind, consent&.id, retry_of&.id, reviewer&.id]
    actual = [previous.origin_id, previous.readiness_id, previous.rule_code, previous.destination_kind,
              previous.consent_id, previous.retry_of_id, previous.retry_requested_by_account_user_id]
    raise JrcContactCenter::OperationError.new('ending_attempt_request_conflict', status: :conflict) unless actual == expected

    previous
  end
end
