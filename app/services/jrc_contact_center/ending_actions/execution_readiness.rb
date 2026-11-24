# frozen_string_literal: true

# Metadata admission only. It never grants source or destination permissions.
# Exact unchanged rules may retain their preceding readiness; changed or
# previously unarmed rules never acquire one from an unrelated catalogue save.
class JrcContactCenter::EndingActions::ExecutionReadiness
  def initialize(account:, origin:)
    @account = account
    @origin = JrcContactCenter::EndingActionOrigin.where(account: account).find(origin.id)
  end

  def call(rule_code)
    JrcContactCenter::EndingActions::PinnedRule.new(account: @account, origin: @origin).call(rule_code)
    relation = JrcContactCenter::EndingActionReadiness.where(account: @account, rule_code: rule_code)
    query = 'cc_ending_action_readiness_matches(jrc_contact_center_ending_action_readinesses.id, ?)'
    relation.where(query, @origin.id).order(id: :desc).first!
  end
end
