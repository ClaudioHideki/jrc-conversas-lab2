# frozen_string_literal: true

class JrcContactCenter::CallLeg < JrcContactCenter::ApplicationRecord
  DIRECTIONS = %w[inbound outbound internal].freeze
  STATUSES = %w[created ringing queued connected held transferred ended failed].freeze

  belongs_to :call_session, class_name: 'JrcContactCenter::CallSession'
  belongs_to :parent_leg, class_name: 'JrcContactCenter::CallLeg', optional: true
  belongs_to :queue, class_name: 'JrcContactCenter::Queue', optional: true
  belongs_to :account_user, optional: true

  validates :started_at, presence: true
  validates :external_leg_id, uniqueness: { scope: :account_id, allow_nil: true }
  validates :direction, inclusion: { in: DIRECTIONS }
  validates :status, inclusion: { in: STATUSES }
  validate :timestamps_are_monotonic
  after_save :ensure_operational_tabulation

  private

  def ensure_operational_tabulation
    return unless saved_change_to_status? || saved_change_to_answered_at? || saved_change_to_ended_at?

    JrcContactCenter::QualificationManager.ensure_voice!(call_session)
  end

  def timestamps_are_monotonic
    errors.add(:answered_at, 'must not be before started_at') if precedes?(answered_at, started_at)
    errors.add(:ended_at, 'must not be before started_at') if precedes?(ended_at, started_at)
    errors.add(:ended_at, 'must not be before answered_at') if precedes?(ended_at, answered_at)
  end

  def precedes?(timestamp, lower_bound)
    timestamp && lower_bound && timestamp < lower_bound
  end
end
