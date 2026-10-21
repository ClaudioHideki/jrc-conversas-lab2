# frozen_string_literal: true

class JrcContactCenter::AgentStateEvent < JrcContactCenter::ApplicationRecord
  STATES = %w[offline available busy ringing in_call acw paused unavailable].freeze

  belongs_to :account_user
  belongs_to :queue, class_name: 'JrcContactCenter::Queue', optional: true

  validates :state, inclusion: { in: STATES }
  validates :source, :started_at, presence: true
  validates :external_event_id, uniqueness: { scope: :account_id, allow_nil: true }
end
