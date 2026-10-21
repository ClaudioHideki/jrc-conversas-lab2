# frozen_string_literal: true

class JrcContactCenter::DailyFact < JrcContactCenter::ApplicationRecord
  DIRECTIONS = %w[inbound outbound mixed].freeze
  COUNTERS = %i[offered_count answered_count abandoned_count transferred_count fallback_count].freeze
  DURATIONS = %i[wait_seconds talk_seconds hold_seconds acw_seconds].freeze

  belongs_to :unit, class_name: 'JrcContactCenter::Unit', optional: true
  belongs_to :queue, class_name: 'JrcContactCenter::Queue', optional: true
  belongs_to :account_user, optional: true

  validates :fact_date, presence: true
  validates :direction, inclusion: { in: DIRECTIONS }
  validates(*COUNTERS, numericality: { only_integer: true, greater_than_or_equal_to: 0 })
  validates(*DURATIONS, numericality: { only_integer: true, greater_than_or_equal_to: 0 })
end
