# frozen_string_literal: true

class JrcContactCenter::QueueMembership < JrcContactCenter::ApplicationRecord
  ROLES = %w[agent supervisor].freeze

  belongs_to :queue, class_name: 'JrcContactCenter::Queue'
  belongs_to :account_user

  validates :role, inclusion: { in: ROLES }
  validates :priority, numericality: { only_integer: true, greater_than: 0 }
  validates :account_user_id, uniqueness: { scope: %i[account_id queue_id] }
  validate :membership_window_order

  private

  def membership_window_order
    errors.add(:ends_at, 'must be after starts_at') if starts_at && ends_at && ends_at <= starts_at
  end
end
