# frozen_string_literal: true

# One native corporate scope within an all-affected review, not another decision or approval engine.
class JrcContactCenter::PauseApprovalScope < JrcContactCenter::ApplicationRecord
  include JrcApprovals::Immutable

  belongs_to :review, class_name: 'JrcContactCenter::PauseApprovalReview', inverse_of: :scopes

  validates :issuer_company_id, :unit_ids, presence: true
end
