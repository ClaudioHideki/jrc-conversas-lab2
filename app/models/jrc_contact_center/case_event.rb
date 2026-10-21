# frozen_string_literal: true

class JrcContactCenter::CaseEvent < JrcContactCenter::ApplicationRecord
  belongs_to :case, class_name: 'JrcContactCenter::Case'
  belongs_to :actor_account_user, class_name: 'AccountUser', optional: true

  validates :event_type, :occurred_at, presence: true
end
