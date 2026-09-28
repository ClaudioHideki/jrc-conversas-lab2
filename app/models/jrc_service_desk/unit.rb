# frozen_string_literal: true

class JrcServiceDesk::Unit < JrcServiceDesk::AccountRecord
  belongs_to :operator_company, class_name: 'JrcServiceDesk::OperatorCompany', optional: false
  has_many :unit_memberships, class_name: 'JrcServiceDesk::UnitMembership', dependent: :restrict_with_error
  has_many :tickets, class_name: 'JrcServiceDesk::Ticket', dependent: :restrict_with_error

  validates :code, presence: true, length: { maximum: 80 }, uniqueness: { scope: %i[account_id operator_company_id] }
  validates :name, presence: true, length: { maximum: 255 }
  validates :active, inclusion: { in: [true, false] }
  validate :operator_account_is_consistent

  protected

  def ownership_columns
    super + [:operator_company_id]
  end

  def operator_account_is_consistent
    validate_account_reference(:operator_company)
  end
end
