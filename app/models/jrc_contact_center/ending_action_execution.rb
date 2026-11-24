# frozen_string_literal: true

# PRIVATE CANDIDATE: requires the separately reviewed owned receipt migration.
# No live task FK: removing a native task must not erase a successful fact.
class JrcContactCenter::EndingActionExecution < JrcContactCenter::ApplicationRecord
  include JrcApprovals::Immutable
  self.record_timestamps = false

  belongs_to :origin, class_name: 'JrcContactCenter::EndingActionOrigin'
  belongs_to :readiness, class_name: 'JrcContactCenter::EndingActionReadiness'
  self.filter_attributes += %i[rule_code request_key integrity_sha256]
end
