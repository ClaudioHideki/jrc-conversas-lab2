class JrcRelationship::PortfolioGroupAssignment < ApplicationRecord
  self.table_name = 'jrc_relationship_portfolio_group_assignments'
  belongs_to :account
  belongs_to :portfolio_group, class_name: 'JrcRelationship::PortfolioGroup'
  belongs_to :assignment, class_name: 'JrcRelationship::Assignment'
  validates :assignment_id, uniqueness: { scope: [:account_id, :portfolio_group_id] }
  validates :active, inclusion: { in: [true, false] }
  validate :native_identity
  validate :unit_identity, if: :active?

  private

  def native_identity
    [portfolio_group, assignment].compact.each do |record|
      errors.add(:base, 'References must belong to this account') unless record.account_id == account_id
    end
  end

  def unit_identity
    return unless portfolio_group&.business_unit_id && assignment

    errors.add(:assignment, 'must belong to the portfolio unit') unless assignment.business_unit_id == portfolio_group.business_unit_id
  end
end
