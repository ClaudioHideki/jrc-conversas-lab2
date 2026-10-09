# frozen_string_literal: true

class JrcServiceDesk::RuleExecution < JrcServiceDesk::TicketRecord
  include JrcServiceDesk::AppendOnly

  belongs_to :rule_version, class_name: 'JrcServiceDesk::OperationalRuleVersion'
  validates :operation_key, presence: true, length: { maximum: 120 }, uniqueness: { scope: %i[account_id unit_id] }
  validate :rule_scope

  private

  def rule_scope
    validate_unit_reference(:rule_version)
    JrcServiceDesk::CanonicalJson.dump(result)
  rescue ArgumentError
    errors.add(:result, 'must be safe JSON')
  end
end
