# frozen_string_literal: true

# Account-owned immutable source receipt. Actor/parent IDs remain historical, not live grants or cascading user associations.
# DeferredPauseRequest remains the one canonical operational pause intent.
class JrcContactCenter::PauseApprovalReview < JrcContactCenter::ApplicationRecord
  include JrcApprovals::Immutable

  has_many :scopes, class_name: 'JrcContactCenter::PauseApprovalScope', foreign_key: :review_id,
                    inverse_of: :review, dependent: :restrict_with_exception

  validates :deferred_pause_request_id, :actor_account_user_id, :actor_user_id, :payload, :context_digest, presence: true
end
