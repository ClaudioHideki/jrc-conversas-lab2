# frozen_string_literal: true

# Actor identifiers are historical receipts, not live grants or cascading user associations.
class JrcContactCenter::IvrDraftVersion < JrcContactCenter::ApplicationRecord
  include JrcApprovals::Immutable

  belongs_to :ivr_draft, class_name: 'JrcContactCenter::IvrDraft', inverse_of: :versions

  validates :revision, numericality: { only_integer: true, greater_than: 0 }
  validates :name, presence: true, length: { maximum: 160 }
  validates :status, inclusion: { in: %w[draft archived] }
  validates :request_id, :actor_account_user_id, :actor_user_id, presence: true
end
