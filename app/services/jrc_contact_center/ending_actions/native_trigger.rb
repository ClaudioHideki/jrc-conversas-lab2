# frozen_string_literal: true

# Classification readiness only, called after original-actor authorization. No
# caller timestamp, draft reason, current rule or early confirmation completes ACW.
class JrcContactCenter::EndingActions::NativeTrigger
  def initialize(origin:)
    @origin = origin
  end

  def call(rule)
    case rule.fetch('timing')
    when 'call_end' then confirmed_classification(rule)
    when 'acw_completed' then completed_acw(rule)
    else raise JrcContactCenter::OperationError, 'ending_action_trigger_unavailable'
    end
  end

  private

  def confirmed_classification(rule)
    row = JrcContactCenter::EndingReasonConfirmation.find_by(
      account_id: @origin.account_id, source_qualification_id: @origin.source_qualification_id,
      actor_account_user_id: @origin.actor_account_user_id, actor_user_id: @origin.actor_user_id,
      catalogue_id: @origin.ending_reason_catalog_id, reason_code: rule.fetch('reason_code')
    )
    return unless row

    { type: 'ending_reason_confirmation', id: row.id, at: [@origin.created_at, row.created_at].max,
      reason_code: row.reason_code, outcome_code: nil }
  end

  def completed_acw(rule)
    row = JrcContactCenter::EndingActionCompletion.find_by(account_id: @origin.account_id, origin_id: @origin.id)
    return unless row && row.reason_code == rule.fetch('reason_code') && matching_native_completion?

    outcomes = rule.fetch('conditions').fetch('outcome_codes')
    return unless outcomes.empty? || outcomes.include?(row.outcome_code)

    { type: 'ending_action_completion', id: row.id, at: row.completed_at, reason_code: row.reason_code, outcome_code: row.outcome_code }
  end

  def matching_native_completion?
    sql = ApplicationRecord.sanitize_sql_array(
      ['SELECT cc_ending_action_completion_matches(?, ?)', @origin.id, @origin.source_qualification_id]
    )
    ApplicationRecord.connection.select_value(sql) == true
  end
end
