# frozen_string_literal: true

class JrcContactCenter::EventInbox < JrcContactCenter::ApplicationRecord
  STATUSES = %w[pending processed failed ignored].freeze

  after_commit :enqueue_reconciliation, on: %i[create update],
                                        if: -> { status == 'pending' && (previously_new_record? || saved_change_to_status?) }

  validates :provider, :external_event_id, :event_type, :schema_version, :occurred_at, :received_at, :payload_digest, presence: true
  validates :external_event_id, uniqueness: { scope: %i[account_id provider] }
  validates :status, inclusion: { in: STATUSES }
  validates :attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  private

  def enqueue_reconciliation
    JrcContactCenter::EventReconcileJob.perform_later(account_id, id) if account.feature_enabled?('jrc_contact_center')
  end
end
