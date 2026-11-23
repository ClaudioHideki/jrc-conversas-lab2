# frozen_string_literal: true

# Private unapplied model. An actual native ACW completion is attested by SQL;
# a reason confirmation alone cannot construct this row or complete the ACW.
class JrcContactCenter::EndingActionCompletion < JrcContactCenter::ApplicationRecord
  include JrcApprovals::Immutable

  belongs_to :origin, class_name: 'JrcContactCenter::EndingActionOrigin'
  alias_attribute :payload, :private_completion_evidence
  self.filter_attributes += %i[payload private_completion_evidence integrity_sha256]
end
