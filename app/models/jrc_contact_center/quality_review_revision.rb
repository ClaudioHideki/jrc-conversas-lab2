# frozen_string_literal: true

# Append-only human correction of an existing authorized native call, never a new analysis catalogue.
class JrcContactCenter::QualityReviewRevision < JrcContactCenter::ApplicationRecord
  include JrcApprovals::Immutable
  self.record_timestamps = false
  self.filter_attributes += %i[original_analysis reviewed_values input_sha256 source_sha256 scope_snapshot]

  belongs_to :recording, class_name: 'TelephonyCallRecord'
  belongs_to :call_session, class_name: 'JrcContactCenter::CallSession'
end
