# frozen_string_literal: true

class JrcServiceDesk::OperatorCompany < JrcServiceDesk::AccountRecord
  has_many :units, class_name: 'JrcServiceDesk::Unit', dependent: :restrict_with_error

  validates :code, presence: true, length: { maximum: 80 }, uniqueness: { scope: :account_id }
  validates :name, presence: true, length: { maximum: 255 }
  validates :active, inclusion: { in: [true, false] }
end
