# frozen_string_literal: true

class JrcContactCenter::Queue < JrcContactCenter::ApplicationRecord
  include JrcContactCenter::AdministrativeAuditable
  STATUSES = %w[active inactive].freeze

  belongs_to :unit, class_name: 'JrcContactCenter::Unit'
  has_many :memberships, class_name: 'JrcContactCenter::QueueMembership', dependent: :restrict_with_error

  validates :code, :name, :service_kind, :strategy, presence: true
  validates :code, uniqueness: { scope: :account_id }, length: { maximum: 80 }
  validates :external_ref, uniqueness: { scope: :account_id, allow_nil: true }
  validates :status, inclusion: { in: STATUSES }
  validates :max_wait_seconds, numericality: { only_integer: true, greater_than: 0, allow_nil: true }
  validate :active_window_order
  validate :native_calendar_binding

  private

  def native_calendar_binding
    key = JrcContactCenter::QueueCalendarState::KEY
    previous = new_record? ? {} : settings_in_database
    return unless settings.key?(key) || previous.key?(key)

    valid = !new_record? && settings.key?(key)
    raise JrcContactCenter::OperationError, 'invalid_queue_calendar_binding' unless valid

    JrcContactCenter::QueueCalendarState.new(queue: self).call
  rescue JrcContactCenter::OperationError, ActiveRecord::RecordNotFound
    errors.add(:settings, 'invalid_queue_calendar_binding')
  end

  def active_window_order
    errors.add(:active_until, 'must be after active_from') if active_from && active_until && active_until <= active_from
  end
end
