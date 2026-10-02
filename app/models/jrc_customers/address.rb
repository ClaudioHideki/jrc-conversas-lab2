class JrcCustomers::Address < ApplicationRecord
  self.table_name = 'company_addresses'
  TYPES = %w[tax billing business installation branch other].freeze
  belongs_to :account
  belongs_to :company, class_name: 'JrcCustomers::Company'
  validates :address_type, inclusion: { in: TYPES }
  validates :country, presence: true, length: { maximum: 100 }
  validates :street, :complement, :district, :city, :state, length: { maximum: 255 }
  validate :same_account

  private

  def same_account
    errors.add(:company_id, 'must belong to this account') unless company&.account_id == account_id
  end
end
