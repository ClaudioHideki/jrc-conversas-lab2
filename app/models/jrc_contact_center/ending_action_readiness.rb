# frozen_string_literal: true

# Owned technical activation evidence, not another rule or business catalogue.
# No endpoint/job/installer creates a readiness implicitly.
class JrcContactCenter::EndingActionReadiness < JrcContactCenter::ApplicationRecord
  include JrcApprovals::Immutable
  self.record_timestamps = false # The database attests created_at; caller dates are rejected.

  belongs_to :version, class_name: 'JrcContactCenter::EndingActionVersion'
  self.filter_attributes += %i[rule_code rule_sha256 request_key]
end
