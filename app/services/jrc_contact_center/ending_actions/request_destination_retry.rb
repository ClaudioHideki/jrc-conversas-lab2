# frozen_string_literal: true

# One selected unsuccessful destination, with a new explicit original-agent
# review. The database preserves its effect key and successful sibling receipts.
class JrcContactCenter::EndingActions::RequestDestinationRetry
  FIELDS = %w[confirmed expected_readiness_id expected_request_id expected_rule_sha256 expected_version_id].freeze

  def initialize(account:, member:, qualification_id:, attempt_id:, request_key:, review:)
    @account = account
    @member = member
    @qualification_id = qualification_id
    @attempt_id = attempt_id
    @key = request_key
    @review = review
  end

  def call
    validate_review!
    raise JrcContactCenter::OperationError, 'ending_execution_requires_independent_transaction' if Account.connection.transaction_open?

    origin_id, caller_id, caller_user_id = reviewed_source_identity
    result, repeated = JrcContactCenter::EndingActions::OriginalActorContext.new(account: @account, origin_id: origin_id).call do |member, origin|
      same = member.id == caller_id && member.user_id == caller_user_id && origin.source_qualification_id.to_s == @qualification_id.to_s
      raise Pundit::NotAuthorizedError unless same

      retry_selected(member, origin)
    end
    JrcContactCenter::EndingActions::DispatchDestinationAttempt.call(result) if repeated
    result
  end

  private

  def reviewed_source_identity
    JrcContactCenter::EndingActions::HistoryContext.new(
      account: @account, member: @member, qualification_id: @qualification_id
    ).call do |member, qualification|
      origins = JrcContactCenter::EndingActionOrigin.where(account: @account, source_qualification_id: qualification.id)
      row = JrcContactCenter::EndingDestinationAttempt.where(account: @account, origin_id: origins.select(:id)).find(@attempt_id)
      original = origins.find(row.origin_id)
      raise Pundit::NotAuthorizedError unless original.actor_account_user_id == member.id && original.actor_user_id == member.user_id

      [original.id, member.id, member.user_id]
    end
  end

  def retry_selected(member, origin)
    previous = JrcContactCenter::EndingDestinationAttempt.where(account: @account, origin: origin).find(@attempt_id)
    verify_review_identity!(previous)
    failure = previous.outcome
    unless failure && %w[failed blocked].include?(failure.outcome)
      raise JrcContactCenter::OperationError.new('ending_pending_review_changed', status: :conflict)
    end

    readiness = JrcContactCenter::EndingActions::SelectedDestinationAuthority.new(
      account: @account, member: member, origin: origin, attempt: previous
    ).call
    persist_retry(member, origin, readiness, previous)
  end

  def verify_review_identity!(previous)
    actual = [previous.readiness_id.to_s, previous.request_key, previous.rule_sha256, previous.version_id.to_s]
    expected = @review.values_at('expected_readiness_id', 'expected_request_id', 'expected_rule_sha256', 'expected_version_id')
    raise JrcContactCenter::OperationError.new('ending_pending_review_changed', status: :conflict) unless actual == expected
  end

  def persist_retry(member, origin, readiness, previous)
    attempts = JrcContactCenter::EndingDestinationAttempt.where(account: @account)
    child = attempts.find_by(retry_of_id: previous.id)
    if child && child.request_key != @key
      raise JrcContactCenter::OperationError.new('ending_attempt_request_conflict', status: :conflict)
    end

    consent = reviewed_consent(member, origin, readiness, previous)
    result = JrcContactCenter::EndingActions::RecordDestinationAttempt.new(
      account: @account, origin: origin, readiness: readiness, rule_code: previous.rule_code, destination_kind: previous.destination_kind
    ).call(request_key: @key, consent: consent, retry_of: previous, reviewer: member)
    [result, child.present?]
  end

  def reviewed_consent(member, origin, readiness, previous)
    return unless origin.version.definition.fetch('entries').find { |row| row.fetch('code') == previous.rule_code }
                        .fetch('execution_mode') == 'agent_confirmation'

    scope = JrcContactCenter::EndingDestinationConsent.where(account: @account)
    consent = scope.find_by(request_key: @key)
    if consent
      actual = [consent.origin_id, consent.readiness_id, consent.rule_code, consent.destination_kind, consent.actor_account_user_id]
      expected = [origin.id, readiness.id, previous.rule_code, previous.destination_kind, member.id]
      raise JrcContactCenter::OperationError.new('ending_attempt_request_conflict', status: :conflict) unless actual == expected

      return consent
    end

    scope.create!(origin: origin, readiness: readiness, actor_account_user_id: member.id,
                  rule_code: previous.rule_code, destination_kind: previous.destination_kind, request_key: @key).reload
  end

  def validate_review!
    valid = @review.is_a?(Hash) && @review.keys.sort == FIELDS && @review['confirmed'] == true
    valid &&= @key.is_a?(String) && @key.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/)
    valid &&= @review.values_at('expected_readiness_id', 'expected_version_id').all? do |value|
      value.is_a?(String) && value.match?(/\A[1-9][0-9]*\z/)
    end
    valid &&= @review['expected_request_id'].is_a?(String) && @review['expected_request_id'].match?(/\A[0-9a-f-]{36}\z/)
    valid &&= @review['expected_rule_sha256'].is_a?(String) && @review['expected_rule_sha256'].match?(/\A[a-f0-9]{64}\z/)
    raise JrcContactCenter::OperationError, 'invalid_ending_pending_review' unless valid
  end
end
