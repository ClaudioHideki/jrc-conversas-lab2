# frozen_string_literal: true

# One bounded terminal result per attempt. Native success commits atomically
# with its effect; failed evidence is appended only after that rollback.
class JrcContactCenter::EndingDestinationOutcome < JrcContactCenter::ApplicationRecord
  include JrcApprovals::Immutable
  self.record_timestamps = false

  belongs_to :attempt, class_name: 'JrcContactCenter::EndingDestinationAttempt', inverse_of: :outcome
  belongs_to :execution, class_name: 'JrcContactCenter::EndingDestinationExecution', optional: true
  self.filter_attributes += %i[integrity_sha256]
end
