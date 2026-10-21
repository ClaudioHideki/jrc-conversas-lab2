# frozen_string_literal: true

class JrcContactCenter::IvrEvent < JrcContactCenter::ApplicationRecord
  belongs_to :call_session, class_name: 'JrcContactCenter::CallSession'

  validates :event_type, :occurred_at, presence: true
  validates :external_event_id, uniqueness: { scope: :account_id, allow_nil: true }
end
