# frozen_string_literal: true

class JrcContactCenter::Callback < JrcContactCenter::ApplicationRecord
  STATES = %w[scheduled in_progress completed failed canceled].freeze

  belongs_to :call_session, class_name: 'JrcContactCenter::CallSession', optional: true
  belongs_to :case, class_name: 'JrcContactCenter::Case', optional: true
  belongs_to :contact, optional: true
  belongs_to :queue, class_name: 'JrcContactCenter::Queue', optional: true
  belongs_to :owner_account_user, class_name: 'AccountUser', optional: true

  validates :idempotency_key, :scheduled_at, presence: true
  validates :idempotency_key, uniqueness: { scope: :account_id }
  validates :state, inclusion: { in: STATES }
  validates :attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :validate_target

  def title
    metadata['title'].presence || "Callback - #{contact&.name.presence || target_phone.presence || "##{id}"}"
  end

  def status
    state
  end

  private

  def validate_target
    errors.add(:base, 'callback target is required') if contact_id.nil? && target_phone.blank?
  end
end
