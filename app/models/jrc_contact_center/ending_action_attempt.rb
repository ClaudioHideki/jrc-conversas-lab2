# frozen_string_literal: true

# Internal durable work evidence, not permission to execute a destination.
# The outcome is appended separately; an unfinished attempt can be reconciled
# against the atomic success ledger without inventing another business record.
class JrcContactCenter::EndingActionAttempt < JrcContactCenter::ApplicationRecord
  include JrcApprovals::Immutable
  self.record_timestamps = false

  belongs_to :origin, class_name: 'JrcContactCenter::EndingActionOrigin'
  belongs_to :readiness, class_name: 'JrcContactCenter::EndingActionReadiness'
  has_one :outcome, class_name: 'JrcContactCenter::EndingActionAttemptOutcome', foreign_key: :attempt_id,
          inverse_of: :attempt, dependent: :restrict_with_exception
  self.filter_attributes += %i[rule_code request_key integrity_sha256]
end
