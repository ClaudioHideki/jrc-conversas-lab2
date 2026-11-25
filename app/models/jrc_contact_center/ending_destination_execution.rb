# frozen_string_literal: true

# Typed success evidence, never a polymorphic authorization shortcut. Resolve
# targets only through their native current visibility/services, not constantize.
class JrcContactCenter::EndingDestinationExecution < JrcContactCenter::ApplicationRecord
  include JrcApprovals::Immutable
  self.record_timestamps = false

  belongs_to :attempt, class_name: 'JrcContactCenter::EndingDestinationAttempt', inverse_of: :execution
  self.filter_attributes += %i[rule_code request_key effect_key rule_sha256 integrity_sha256]
end
