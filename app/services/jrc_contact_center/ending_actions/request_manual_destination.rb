# frozen_string_literal: true

# One explicitly reviewed action, never a qualification-wide execution command.
# Root consent is separate from classification and ACW, and conveys no grant.
# A controller/presenter and selected terminal retry remain a separate boundary.
class JrcContactCenter::EndingActions::RequestManualDestination
  NATIVE_OPTIONS = %i[destination_kind origin_id request_key review rule_code].freeze
  REVIEW_FIELDS = %w[confirmed expected_readiness_id expected_rule_sha256 expected_version_id].freeze

  def initialize(account:, member:, qualification_id:, **options)
    raise ArgumentError, 'Exact native destination options required' unless options.keys.sort == NATIVE_OPTIONS

    @account = account
    @member = member
    @qualification_id = qualification_id
    @origin_id = options.fetch(:origin_id)
    @code = options.fetch(:rule_code)
    @kind = options.fetch(:destination_kind)
    @key = options.fetch(:request_key)
    @review = options.fetch(:review)
  end

  def call
    validate_review!
    raise JrcContactCenter::OperationError, 'ending_execution_requires_independent_transaction' if Account.connection.transaction_open?

    attempt, repeated = reviewed_intent
    # The first attempt's native after-commit callback owns initial delivery.
    # An uncertain response can request delivery of that same durable intent;
    # it never creates a replacement consent or another root operation.
    JrcContactCenter::EndingActions::DispatchDestinationAttempt.call(attempt) if repeated
    attempt
  end

  private

  def reviewed_intent
    origin_id, caller_id, caller_user_id = reviewed_source_identity
    # Close the read boundary first; the native independent transaction performs
    # current source/role checks again and cannot borrow the earlier read grant.
    JrcContactCenter::EndingActions::OriginalActorContext.new(account: @account, origin_id: origin_id).call do |member, origin|
      same = member.id == caller_id && member.user_id == caller_user_id && origin.source_qualification_id.to_s == @qualification_id.to_s
      raise Pundit::NotAuthorizedError unless same

      persist_reviewed_intent(member, origin)
    end
  end

  def reviewed_source_identity
    context = JrcContactCenter::EndingActions::HistoryContext.new(
      account: @account, member: @member, qualification_id: @qualification_id
    )
    context.call do |caller, qualification|
      origin = JrcContactCenter::EndingActionOrigin.where(account: @account, source_qualification_id: qualification.id).find(@origin_id)
      raise Pundit::NotAuthorizedError unless origin.actor_account_user_id == caller.id && origin.actor_user_id == caller.user_id

      [origin.id, caller.id, caller.user_id]
    end
  end

  def persist_reviewed_intent(member, origin)
    rule = JrcContactCenter::EndingActions::PinnedRule.new(account: @account, origin: origin).call(@code)
    valid = rule['destination_schema_version'] == 2 && rule.fetch('execution_mode') == 'agent_confirmation'
    raise JrcContactCenter::OperationError, 'ending_action_requires_agent_confirmation' unless valid

    action = rule.fetch('actions').find { |row| row.fetch('kind') == @kind }
    raise JrcContactCenter::OperationError, 'ending_action_destination_unavailable' unless action

    # This is the same native destination authority as the editor, independent
    # of configure permission. CRM additionally requires the original customer.
    JrcContactCenter::EndingActions::ConfiguredNativeAction.new(account: @account, member: member).call(action, active: true)
    if @kind == 'crm'
      JrcContactCenter::EndingActions::OriginalCustomerReference.new(account: @account, member: member, origin: origin).call
    end
    readiness = readiness_for_existing_or_new_root(origin)
    triggered = JrcContactCenter::EndingActions::NativeTrigger.new(origin: origin).call(rule)
    raise JrcContactCenter::OperationError, 'ending_action_trigger_pending' unless triggered

    verify_metadata!(origin, readiness)
    record_root(member, origin, readiness)
  end

  def readiness_for_existing_or_new_root(origin)
    root = JrcContactCenter::EndingDestinationAttempt.where(account: @account, origin: origin, rule_code: @code,
                                                           destination_kind: @kind, retry_of_id: nil).first
    return JrcContactCenter::EndingActions::ExecutionReadiness.new(account: @account, origin: origin).call(@code) unless root

    raise JrcContactCenter::OperationError.new('ending_attempt_request_conflict', status: :conflict) unless root.request_key == @key

    readiness = JrcContactCenter::EndingActionReadiness.where(account: @account).find(root.readiness_id)
    sql = ApplicationRecord.sanitize_sql_array(['SELECT cc_ending_action_readiness_matches(?, ?)', readiness.id, origin.id])
    matches = ApplicationRecord.connection.select_value(sql) == true
    raise JrcContactCenter::OperationError.new('ending_pending_review_changed', status: :conflict) unless matches

    readiness
  end

  def verify_metadata!(origin, readiness)
    query = ApplicationRecord.sanitize_sql_array([
      "SELECT cc_ending_destination_context(?, ?, ?, ?, ?) ->> 'rule_sha256'",
      @account.id, origin.id, readiness.id, @code, @kind
    ])
    digest = ApplicationRecord.connection.select_value(query)
    actual = [readiness.id.to_s, origin.version_id.to_s, digest]
    expected = @review.values_at('expected_readiness_id', 'expected_version_id', 'expected_rule_sha256')
    raise JrcContactCenter::OperationError.new('ending_pending_review_changed', status: :conflict) unless actual == expected
  end

  def record_root(member, origin, readiness)
    roots = JrcContactCenter::EndingDestinationAttempt.where(account: @account, origin: origin, rule_code: @code,
                                                            destination_kind: @kind, retry_of_id: nil)
    previous = roots.first
    if previous && previous.request_key != @key
      raise JrcContactCenter::OperationError.new('ending_attempt_request_conflict', status: :conflict)
    end
    consent = reviewed_consent(member, origin, readiness)
    attempt = JrcContactCenter::EndingActions::RecordDestinationAttempt.new(
      account: @account, origin: origin, readiness: readiness, rule_code: @code, destination_kind: @kind
    ).call(request_key: @key, consent: consent)
    [attempt, previous.present?]
  end

  def reviewed_consent(member, origin, readiness)
    scope = JrcContactCenter::EndingDestinationConsent.where(account: @account)
    previous = scope.find_by(request_key: @key)
    if previous
      actual = [previous.origin_id, previous.readiness_id, previous.rule_code, previous.destination_kind, previous.actor_account_user_id]
      expected = [origin.id, readiness.id, @code, @kind, member.id]
      raise JrcContactCenter::OperationError.new('ending_attempt_request_conflict', status: :conflict) unless actual == expected

      return previous
    end
    scope.create!(origin: origin, readiness: readiness, rule_code: @code, destination_kind: @kind,
                  actor_account_user_id: member.id, request_key: @key).reload
  end

  def validate_review!
    JrcContactCenter::EndingActions::DestinationSelectionReview.new(@review, request_id: false).validate!
    valid = @key.is_a?(String) && @key.match?(/\A[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\z/)
    raise JrcContactCenter::OperationError, 'invalid_ending_pending_review' unless valid
  end

end
