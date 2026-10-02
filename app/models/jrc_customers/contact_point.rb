class JrcCustomers::ContactPoint < ApplicationRecord
  self.table_name = 'contact_points'
  KINDS = (JrcCustomers::Identity::EMAIL_KINDS + JrcCustomers::Identity::PHONE_KINDS + ['extension']).freeze
  belongs_to :account
  belongs_to :contact
  before_validation :normalize_value
  validates :kind, inclusion: { in: KINDS }
  validates :value, :normalized_value, presence: true, length: { maximum: 255 }
  validates :normalized_value, uniqueness: { scope: [:contact_id, :kind] }
  validate :same_account

  private

  def normalize_value
    self.normalized_value = JrcCustomers::Identity.point(kind, value)
  end

  def same_account
    errors.add(:contact_id, 'must belong to this account') unless contact&.account_id == account_id
  end
end
