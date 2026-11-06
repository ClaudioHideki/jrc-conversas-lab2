# A named grouping of existing native customer allocations, never a customer
# registry or an implicit grant to its customers or original source modules.
class JrcRelationship::PortfolioGroup < ApplicationRecord
  GOAL_FIELDS = %w[metric baseline target current unit].freeze
  NUMERIC_GOAL_FIELDS = %w[baseline target current].freeze
  self.table_name = 'jrc_relationship_portfolio_groups'
  belongs_to :account
  belongs_to :owner, class_name: 'User'
  belongs_to :team, optional: true
  belongs_to :business_unit, class_name: 'JrcCrm::BusinessUnit', optional: true
  belongs_to :segment, class_name: 'JrcCustomers::Taxonomy', optional: true
  has_many :customer_links, class_name: 'JrcRelationship::PortfolioGroupAssignment', dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 120 }, uniqueness: { scope: :account_id, case_sensitive: false }
  validates :objective, length: { maximum: 4000 }
  validates :status, inclusion: { in: %w[active archived] }
  validates :visibility, inclusion: { in: %w[private team account] }
  validates :team, presence: true, if: -> { visibility == 'team' }
  validate :tenant_references
  validate :bounded_goals
  validate :eligible_coordinator

  private

  def eligible_coordinator
    return unless status == 'active' && (new_record? || will_save_change_to_owner_id? || will_save_change_to_status?)

    JrcRelationship::DistributionApproval.lock_configuration!(account_id)
    return if JrcRelationship::AnalystEligibility.available?(account_id, owner_id)

    errors.add(:owner, 'is withdrawn from Relationship; choose an eligible current coordinator')
  end

  def tenant_references
    %i[team business_unit segment].each do |key|
      value = public_send(key)
      errors.add(key, 'must belong to this account') if value && value.account_id != account_id
    end
    errors.add(:owner, 'must belong to this account') unless AccountUser.exists?(account_id: account_id, user_id: owner_id)
    errors.add(:segment, 'must be a customer segment') if segment && segment.kind != 'segment'
  end

  def bounded_goals
    valid = goals.is_a?(Array) && goals.size <= 50 && goals.to_json.bytesize <= 64.kilobytes
    return errors.add(:goals, 'must contain at most50 bounded metrics') unless valid

    goals.each do |goal|
      errors.add(:goals, 'use bounded named metrics and finite explicit values') unless valid_goal?(goal)
    end
  end

  def valid_goal?(goal)
    return false unless valid_goal_shape?(goal)

    numeric_goal_values?(goal) && (!goal.key?('unit') || (goal['unit'].is_a?(String) && goal['unit'].length <= 40))
  end

  def valid_goal_shape?(goal)
    goal.is_a?(Hash) && (goal.keys - GOAL_FIELDS).empty? && goal['metric'].is_a?(String) && goal['metric'].strip.length.between?(1, 200)
  end

  def numeric_goal_values?(goal)
    NUMERIC_GOAL_FIELDS.all? { |key| !goal.key?(key) || (goal[key].is_a?(Numeric) && goal[key].finite?) }
  end
end
