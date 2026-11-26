# frozen_string_literal: true

# Read-only current authority for one immutable typed attempt. Shared by the
# UI capability projection and the independently reauthorized selected command.
class JrcContactCenter::EndingActions::SelectedDestinationAuthority
  def initialize(account:, member:, origin:, attempt:)
    @account = account
    @member = member
    @origin = origin
    @attempt = attempt
  end

  def call
    own = @attempt.account_id == @account.id && @attempt.origin_id == @origin.id &&
          @origin.actor_account_user_id == @member.id && @origin.actor_user_id == @member.user_id
    raise Pundit::NotAuthorizedError unless own

    JrcContactCenter::EndingActions::SourceAuthority.new(account: @account, member: @member).call(@origin)
    authorize_native_action!
    readiness = JrcContactCenter::EndingActionReadiness.where(account: @account).find(@attempt.readiness_id)
    verify_exact_readiness!(readiness)
    readiness
  end

  private

  def authorize_native_action!
    rule = JrcContactCenter::EndingActions::PinnedRule.new(account: @account, origin: @origin).call(@attempt.rule_code)
    raise JrcContactCenter::OperationError, 'ending_action_destination_unavailable' unless rule['destination_schema_version'] == 2

    action = rule.fetch('actions').find { |row| row.fetch('kind') == @attempt.destination_kind }
    raise JrcContactCenter::OperationError, 'ending_action_destination_unavailable' unless action

    JrcContactCenter::EndingActions::ConfiguredNativeAction.new(account: @account, member: @member).call(action, active: true)
    return unless %w[crm service_desk].include?(@attempt.destination_kind)

    JrcContactCenter::EndingActions::OriginalCustomerReference.new(account: @account, member: @member, origin: @origin).call
  end

  def verify_exact_readiness!(readiness)
    sql = [
      'SELECT cc_ending_destination_context(?, ?, ?, ?, ?)::text',
      @account.id, @origin.id, readiness.id, @attempt.rule_code, @attempt.destination_kind
    ]
    sql = ApplicationRecord.sanitize_sql_array(sql)
    actual = JSON.parse(ApplicationRecord.connection.select_value(sql))
    expected = @attempt.attributes.slice('origin_id', 'readiness_id', 'version_id', 'actor_account_user_id', 'actor_user_id',
                                         'rule_code', 'destination_kind', 'operation', 'rule_sha256')
    raise JrcContactCenter::OperationError.new('ending_pending_review_changed', status: :conflict) unless actual.slice(*expected.keys) == expected
  end
end
