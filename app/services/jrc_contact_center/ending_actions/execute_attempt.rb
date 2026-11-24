# frozen_string_literal: true

# Internal worker command; no caller-supplied actor or destination attributes.
# Each unfinished attempt is reauthorized through the original native command.
# The successful result commits with the Task/audit/receipt. A failed result is
# appended only after that transaction has rolled back, retaining no raw error.
class JrcContactCenter::EndingActions::ExecuteAttempt
  def initialize(account:, attempt_id:)
    @account = account
    @attempt_id = attempt_id
  end

  def call
    @attempt = nil
    raise JrcContactCenter::OperationError, 'ending_execution_requires_independent_transaction' if Account.connection.transaction_open?

    @attempt = JrcContactCenter::EndingActionAttempt.where(account: @account).find(@attempt_id)
    # An identical terminal delivery is an internal acknowledgement, not a new
    # attempt, an access API or permission to read a destination. Every unfinished
    # or newly requested attempt still enters the original native authority path.
    return @attempt.outcome if @attempt.outcome

    command = JrcContactCenter::EndingActions::ExecuteProjectTask.new(account: @account, origin_id: @attempt.origin_id,
                                                                      rule_code: @attempt.rule_code)
    command.call do |metadata, &effect|
      verify_identity!(metadata)
      outcomes.first || outcomes.create!(outcome: 'succeeded', result_code: 'completed', execution: effect.call).reload
    end
  rescue StandardError => e
    raise unless @attempt

    append_failure!(e)
  end

  private

  def outcomes
    JrcContactCenter::EndingActionAttemptOutcome.where(account: @account, attempt: @attempt)
  end

  def verify_identity!(metadata)
    actual = @attempt.attributes.symbolize_keys.slice(*metadata.keys)
    raise JrcContactCenter::OperationError, 'ending_attempt_identity_mismatch' unless metadata == actual
  end

  def append_failure!(error)
    # This lock serializes history writers with deactivation and account removal.
    # It does not authorize a destination or revive a blocked attempt. Inactive
    # accounts may retain the fact of a refused attempt without gaining access.
    @account.with_lock('FOR NO KEY UPDATE') do
      previous = outcomes.first
      next previous if previous

      kind, code = JrcContactCenter::EndingActions::AttemptFailure.call(error)
      outcomes.create!(outcome: kind, result_code: code).reload
    end
  end
end
