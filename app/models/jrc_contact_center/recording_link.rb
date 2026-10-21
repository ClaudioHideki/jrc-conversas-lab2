# frozen_string_literal: true

class JrcContactCenter::RecordingLink < JrcContactCenter::ApplicationRecord
  STATUSES = %w[pending available expired revoked].freeze

  belongs_to :call_session, class_name: 'JrcContactCenter::CallSession'
  belongs_to :call_leg, class_name: 'JrcContactCenter::CallLeg', optional: true

  validates :provider, :external_recording_id, presence: true
  validates :external_recording_id, uniqueness: { scope: %i[account_id provider] }
  validates :status, inclusion: { in: STATUSES }
  validates :duration_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0, allow_nil: true }
end
