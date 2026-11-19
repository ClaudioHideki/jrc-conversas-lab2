# frozen_string_literal: true

class JrcContactCenter::DeferredPauseRequest < JrcContactCenter::ApplicationRecord
  STATES = %w[pending blocked applied cancelled].freeze

  belongs_to :account_user
  scope :active, -> { where(state: %w[pending blocked]) }

  validates :state, inclusion: { in: STATES }
  validates :request_id, :request_digest, :catalog_revision, :reason_code, :reason_label, presence: true
  validate :member_belongs_to_account

  def operator_payload
    attributes.slice('request_id', 'state', 'reason_code', 'reason_label', 'queue_id', 'justification', 'created_at', 'failure_code')
              .merge('queue_id' => queue_id&.to_s, 'local_only' => true, 'provider_confirmed' => false)
  end

  private

  def member_belongs_to_account
    errors.add(:account_user, 'unavailable') unless account_user&.account_id == account_id
  end
end
