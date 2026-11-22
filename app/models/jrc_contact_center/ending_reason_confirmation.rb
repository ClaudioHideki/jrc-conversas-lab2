# frozen_string_literal: true

# Classification evidence only; neither ACW completion nor permission to mutate another module.
class JrcContactCenter::EndingReasonConfirmation < JrcContactCenter::ApplicationRecord
  include JrcApprovals::Immutable

  belongs_to :qualification, class_name: 'JrcContactCenter::Qualification', optional: true
  self.filter_attributes += %i[payload input_digest]

  validates :request_key, :input_digest, :reason_code, presence: true
end
