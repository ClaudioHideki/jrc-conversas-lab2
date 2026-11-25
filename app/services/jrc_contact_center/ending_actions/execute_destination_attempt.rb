# frozen_string_literal: true

# Internal native worker boundary for one immutable typed attempt. No actor,
# source, native target or replacement rule parameters come from a caller.
# A failed native transaction rolls back before bounded failure evidence is
# appended; successful siblings have independent transactions and receipts.
class JrcContactCenter::EndingActions::ExecuteDestinationAttempt
  def initialize(account:, attempt_id:)
    @account = account
    @attempt_id = attempt_id
  end

  def call
    @attempt = nil
    raise JrcContactCenter::OperationError, 'ending_execution_requires_independent_transaction' if Account.connection.transaction_open?

    @attempt = JrcContactCenter::EndingDestinationAttempt.where(account: @account).find(@attempt_id)
    # A terminal redelivery is an internal acknowledgement only. This command
    # is not a read API and exposes no native record or private project detail.
    return @attempt.outcome if @attempt.outcome

    JrcContactCenter::EndingActions::OriginalActorContext.new(account: @account, origin_id: @attempt.origin_id).call do |member, origin|
      @attempt.reload
      outcomes.first || execute!(member, origin)
    end
  rescue StandardError => e
    raise unless @attempt

    append_failure!(e)
  end

  private

  def outcomes
    JrcContactCenter::EndingDestinationOutcome.where(account: @account, attempt: @attempt)
  end

  def execute!(member, origin)
    rule = JrcContactCenter::EndingActions::PinnedRule.new(account: @account, origin: origin).call(@attempt.rule_code)
    raise JrcContactCenter::OperationError, 'ending_action_destination_unavailable' unless rule['destination_schema_version'] == 2

    verify_identity!
    readiness = JrcContactCenter::EndingActionReadiness.where(account: @account).find(@attempt.readiness_id)
    action = rule.fetch('actions').find { |row| row.fetch('kind') == @attempt.destination_kind }
    raise JrcContactCenter::OperationError, 'ending_action_destination_unavailable' unless action

    target = JrcContactCenter::EndingActions::ExecuteNativeDestination.new(
      account: @account, member: member, origin: origin, attempt: @attempt
    ).call(action: action, readiness: readiness)
    execution = JrcContactCenter::EndingDestinationExecution.create!(account: @account, attempt: @attempt, target_id: target.id).reload
    outcomes.create!(outcome: 'succeeded', result_code: 'completed', execution: execution).reload
  end

  def verify_identity!
    # Compare the exact stored attempt to current database-derived provenance.
    # Avoid timezone-dependent Ruby reconstruction or selecting a newer arming
    # receipt. This proves identity, not source/destination authorization.
    query = ApplicationRecord.sanitize_sql_array([
      "SELECT to_jsonb(evidence) @> (cc_ending_destination_context(?, ?, ?, ?, ?) - 'execution_mode' - 'source_timezone') " \
      'FROM jrc_contact_center_ending_destination_attempts evidence WHERE evidence.account_id = ? AND evidence.id = ?',
      @account.id, @attempt.origin_id, @attempt.readiness_id, @attempt.rule_code, @attempt.destination_kind,
      @account.id, @attempt.id
    ])
    return if ApplicationRecord.connection.select_value(query) == true

    raise JrcContactCenter::OperationError, 'ending_attempt_identity_mismatch'
  end

  def append_failure!(error)
    # Account removal/deactivation can preserve the fact of a refused attempt.
    # This lock does not authorize a destination, retry a terminal attempt or
    # revive work permanently blocked by an intervening rule deactivation.
    @account.with_lock('FOR NO KEY UPDATE') do
      previous = outcomes.first
      next previous if previous

      kind, code = JrcContactCenter::EndingActions::AttemptFailure.call(error)
      outcomes.create!(outcome: kind, result_code: code).reload
    end
  end
end
