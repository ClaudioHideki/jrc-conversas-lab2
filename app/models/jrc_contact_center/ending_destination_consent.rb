# frozen_string_literal: true

# Technical action consent only. It is separate from ending-reason confirmation
# and ACW completion, and never grants current source or destination authority.
class JrcContactCenter::EndingDestinationConsent < JrcContactCenter::ApplicationRecord
  include JrcApprovals::Immutable
  self.record_timestamps = false

  belongs_to :origin, class_name: 'JrcContactCenter::EndingActionOrigin'
  belongs_to :readiness, class_name: 'JrcContactCenter::EndingActionReadiness'
  has_one :attempt, class_name: 'JrcContactCenter::EndingDestinationAttempt', foreign_key: :consent_id,
                    inverse_of: :consent, dependent: :restrict_with_exception
  self.filter_attributes += %i[rule_code request_key rule_sha256 integrity_sha256]
end
