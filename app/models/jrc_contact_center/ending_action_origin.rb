# frozen_string_literal: true

# Private unapplied model. Populated only by the native pending-event SQL guard,
# never a user-supplied call, actor, scope or historical reconstruction.
class JrcContactCenter::EndingActionOrigin < JrcContactCenter::ApplicationRecord
  include JrcApprovals::Immutable

  belongs_to :qualification, class_name: 'JrcContactCenter::Qualification', optional: true
  belongs_to :version, class_name: 'JrcContactCenter::EndingActionVersion'
  belongs_to :queue_scope_version, class_name: 'JrcContactCenter::EndingActionQueueScope'
  alias_attribute :payload, :private_origin_evidence
  self.filter_attributes += %i[payload private_origin_evidence integrity_sha256]
end
