# frozen_string_literal: true

# Internal scheduling boundary only. A caller must already hold this account's
# native lock. Immutable source/readiness evidence is not an execution grant.
class JrcContactCenter::EndingActions::RecordAttempt
  def initialize(account:, origin:, rule_code:, readiness:, request_key:)
    @account = account
    @origin = origin
    @code = rule_code
    @readiness = readiness
    @request_key = request_key
  end

  def call
    scope = JrcContactCenter::EndingActionAttempt.where(account: @account)
    previous = scope.find_by(request_key: @request_key)
    return replay!(previous) if previous

    scope.create!(origin: @origin, readiness: @readiness, rule_code: @code, destination_kind: 'project_task',
                  request_key: @request_key).reload
  end

  private

  def replay!(previous)
    expected = [@origin.id, @readiness.id, @code, 'project_task']
    actual = [previous.origin_id, previous.readiness_id, previous.rule_code, previous.destination_kind]
    raise JrcContactCenter::OperationError.new('ending_attempt_request_conflict', status: :conflict) unless actual == expected

    previous
  end
end
