# frozen_string_literal: true

class JrcContactCenter::RoutingRule < JrcContactCenter::ApplicationRecord
  KINDS = %w[ddd customer portfolio service fallback].freeze
  STATES = %w[draft published retired].freeze

  belongs_to :target_unit, class_name: 'JrcContactCenter::Unit', optional: true
  belongs_to :target_queue, class_name: 'JrcContactCenter::Queue', optional: true
  belongs_to :created_by_account_user, class_name: 'AccountUser'

  validates :version, numericality: { only_integer: true, greater_than: 0 }
  validates :priority, numericality: { only_integer: true, greater_than: 0 }
  validates :rule_key, presence: true, uniqueness: { scope: %i[account_id version] }
  validates :kind, inclusion: { in: KINDS }
  validates :state, inclusion: { in: STATES }
  validate :validate_target
  validate :routing_window_order

  private

  def validate_target
    errors.add(:base, 'routing target is required') unless target_unit_id || target_queue_id
  end

  def routing_window_order
    errors.add(:ends_at, 'must be after starts_at') if starts_at && ends_at && ends_at <= starts_at
  end
end
