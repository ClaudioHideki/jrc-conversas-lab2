# frozen_string_literal: true

# Account-owned reusable form identity. Only append-only versions carry editable fields.
class JrcContactCenter::AcwFormTemplate < JrcContactCenter::ApplicationRecord
  include JrcApprovals::Immutable

  has_many :versions, class_name: 'JrcContactCenter::AcwFormVersion', inverse_of: :acw_form_template, dependent: :restrict_with_exception

  def latest_version
    versions.where(account_id: account_id).order(revision: :desc).first!
  end
end
