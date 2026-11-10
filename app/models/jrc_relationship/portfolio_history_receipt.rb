class JrcRelationship::PortfolioHistoryReceipt < ApplicationRecord
  self.table_name = 'jrc_relationship_portfolio_history_receipts'
  belongs_to :account
  belongs_to :portfolio_group, class_name: 'JrcRelationship::PortfolioGroup'
  belongs_to :audit_event, class_name: 'JrcCrm::AuditEvent'
  validates :audit_event_id, uniqueness: true
  validates :digest, format: { with: /\A[0-9a-f]{64}\z/ }
  validate :native_scope_and_digest
  before_update { raise ActiveRecord::ReadOnlyRecord, 'Portfolio history receipts are immutable' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Portfolio history receipts are immutable' }

  private

  def native_scope_and_digest
    unless portfolio_group&.account_id == account_id && audit_event&.account_id == account_id &&
           JrcRelationship::PortfolioHistoryBoundary.valid?(snapshot) &&
           snapshot['account_id'] == account_id && snapshot['group_id'] == portfolio_group_id &&
           JrcRelationship::PortfolioHistoryBoundary.digest(snapshot) == digest &&
           snapshot['event_digest'] == JrcRelationship::PortfolioHistoryDetails.event_digest(audit_event)
      errors.add(:base, 'Use an exact native scoped audit snapshot')
    end
  end
end
