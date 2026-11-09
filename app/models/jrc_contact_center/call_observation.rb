# frozen_string_literal: true

class JrcContactCenter::CallObservation < JrcContactCenter::ApplicationRecord
  belongs_to :call_session, class_name: 'JrcContactCenter::CallSession'
  belongs_to :author_user, class_name: 'User', optional: true

  validates :text, length: { maximum: 1000 }, allow_blank: true
  validates :call_version, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # No editing/deletion endpoint: saved revisions are append-only in the application.
  def readonly?
    persisted?
  end
end
