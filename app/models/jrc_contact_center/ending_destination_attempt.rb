# frozen_string_literal: true

# Technical typed attempt within the existing EndingActions flow. Successful
# siblings and the immutable Project-only v1 history remain independent.
class JrcContactCenter::EndingDestinationAttempt < JrcContactCenter::ApplicationRecord
  include JrcApprovals::Immutable
  self.record_timestamps = false

  belongs_to :origin, class_name: 'JrcContactCenter::EndingActionOrigin'
  belongs_to :readiness, class_name: 'JrcContactCenter::EndingActionReadiness'
  belongs_to :consent, class_name: 'JrcContactCenter::EndingDestinationConsent', optional: true, inverse_of: :attempt
  belongs_to :retry_of, class_name: 'JrcContactCenter::EndingDestinationAttempt', optional: true
  has_one :execution, class_name: 'JrcContactCenter::EndingDestinationExecution', foreign_key: :attempt_id,
                      inverse_of: :attempt, dependent: :restrict_with_exception
  has_one :outcome, class_name: 'JrcContactCenter::EndingDestinationOutcome', foreign_key: :attempt_id,
                    inverse_of: :attempt, dependent: :restrict_with_exception
  self.filter_attributes += %i[rule_code request_key effect_key rule_sha256 integrity_sha256]
end
