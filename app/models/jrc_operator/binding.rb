class JrcOperator::Binding < ApplicationRecord
  self.table_name = 'jrc_operator_bindings'
  belongs_to :account
  belongs_to :contact
  belongs_to :company, class_name: 'JrcCustomers::Company'
  belongs_to :business_unit, class_name: 'JrcCrm::BusinessUnit'
  has_many :operations, class_name: 'JrcOperator::Operation', dependent: :restrict_with_error
  validates :bemtevi_customer_id, format: { with: /\A[1-9]\d{0,12}\z/ }
  validate :valid_scope
  validate :immutable_identity, on: :update

  private

  def valid_scope
    errors.add(:base, 'Invalid integration scope') unless account_scope_valid? && operational_company_valid? && inbox_scope_valid?
  end

  def account_scope_valid?
    [contact, company, business_unit].all? { |row| row && row.account_id == account_id }
  end

  def operational_company_valid?
    business_unit.company_id == company_id && business_unit.active? && company.active? && company.relationship_type == 'internal'
  end

  def inbox_scope_valid?
    allowed_inbox_ids.is_a?(Array) && allowed_inbox_ids.all? { |id| id.is_a?(Integer) && id.positive? } &&
      account.inboxes.where(id: allowed_inbox_ids).count == allowed_inbox_ids.uniq.size
  end

  def immutable_identity
    keys = %w[account_id contact_id company_id business_unit_id bemtevi_customer_id]
    errors.add(:base, 'Create a new binding when external identity changes') if keys.any? { |key| will_save_change_to_attribute?(key) }
  end
end
