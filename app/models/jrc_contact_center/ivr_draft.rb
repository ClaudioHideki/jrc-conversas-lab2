# frozen_string_literal: true

# Immutable account/unit identity; editable values belong to append-only revisions.
class JrcContactCenter::IvrDraft < JrcContactCenter::ApplicationRecord
  include JrcApprovals::Immutable

  belongs_to :unit, class_name: 'JrcContactCenter::Unit'
  has_many :versions, class_name: 'JrcContactCenter::IvrDraftVersion', inverse_of: :ivr_draft, dependent: :restrict_with_exception

  def latest_version
    versions.where(account_id: account_id).order(revision: :desc).first!
  end
end
