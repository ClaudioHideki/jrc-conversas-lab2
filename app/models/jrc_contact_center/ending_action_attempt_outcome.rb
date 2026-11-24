# frozen_string_literal: true

# An append-only outcome contains bounded machine codes and immutable success
# references, never exception messages, private templates or client content.
class JrcContactCenter::EndingActionAttemptOutcome < JrcContactCenter::ApplicationRecord
  include JrcApprovals::Immutable
  self.record_timestamps = false

  belongs_to :attempt, class_name: 'JrcContactCenter::EndingActionAttempt', inverse_of: :outcome
  belongs_to :execution, class_name: 'JrcContactCenter::EndingActionExecution', optional: true
  self.filter_attributes += %i[integrity_sha256]
end
