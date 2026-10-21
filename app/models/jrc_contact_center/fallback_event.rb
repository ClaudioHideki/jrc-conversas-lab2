# frozen_string_literal: true

class JrcContactCenter::FallbackEvent < JrcContactCenter::ApplicationRecord
  RESULTS = %w[requested confirmed rejected failed terminal].freeze

  belongs_to :call_session, class_name: 'JrcContactCenter::CallSession'
  belongs_to :source_unit, class_name: 'JrcContactCenter::Unit', optional: true
  belongs_to :source_queue, class_name: 'JrcContactCenter::Queue', optional: true
  belongs_to :target_queue, class_name: 'JrcContactCenter::Queue', optional: true

  validates :reason_code, :occurred_at, presence: true
  validates :result, inclusion: { in: RESULTS }
end
