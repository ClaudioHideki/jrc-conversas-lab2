# frozen_string_literal: true

class JrcContactCenter::Unit < JrcContactCenter::ApplicationRecord
  KINDS = %w[sac finance coe administrative].freeze
  STATUSES = %w[active inactive].freeze

  belongs_to :parent_unit, class_name: 'JrcContactCenter::Unit', optional: true
  has_many :child_units, class_name: 'JrcContactCenter::Unit', foreign_key: :parent_unit_id, inverse_of: :parent_unit, dependent: :restrict_with_error
  has_many :queues, class_name: 'JrcContactCenter::Queue', dependent: :restrict_with_error

  validates :code, :name, presence: true
  validates :code, uniqueness: { scope: :account_id }, length: { maximum: 80 }
  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :timezone, presence: true
  validate :known_timezone

  private

  def known_timezone
    errors.add(:timezone, 'is invalid') unless Time.find_zone(timezone)
  end
end
