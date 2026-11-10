class JrcBackoffice::RequirementRule < ApplicationRecord
  self.table_name = 'jrc_backoffice_requirement_rules'
  belongs_to :account
  belongs_to :created_by, class_name: 'User'
  belongs_to :business_unit, class_name: 'JrcCrm::BusinessUnit', optional: true
  belongs_to :product, class_name: 'JrcCrm::Product', optional: true
  validates :rule_key, format: { with: /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/ }
  validates :version, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: %i[account_id rule_key] }
  validates :state, inclusion: { in: %w[active archived] }
  validates :operation, inclusion: { in: %w[fulfillment approval change cancellation] }, allow_nil: true
  validates :customer_kind, inclusion: { in: %w[individual company] }, allow_nil: true
  validates :reason, length: { minimum: 1, maximum: 4000 }
  validate :valid_definition
  validate :same_account
  before_update { raise ActiveRecord::ReadOnlyRecord, 'Requirement revisions are immutable' }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, 'Requirement revisions are immutable' }

  private

  def valid_definition
    JrcBackoffice::RequirementDefinition.normalize(definition)
  rescue ArgumentError => error
    errors.add(:definition, error.message)
  end

  def same_account
    %i[product business_unit].each do |name|
      value = public_send(name)
      errors.add(name, 'must belong to this account') if value && value.account_id != account_id
    end
    errors.add(:created_by, 'must belong to this account') unless AccountUser.exists?(account_id: account_id, user_id: created_by_id)
  end
end
