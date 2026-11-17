class JrcContactCenter::AccessGrant < ApplicationRecord
  self.table_name = 'jrc_contact_center_access_grants'

  include JrcContactCenter::AdministrativeAuditable

  belongs_to :account
  belongs_to :account_user, optional: true
  belongs_to :team, optional: true

  attr_readonly :account_id, :account_user_id, :team_id

  validates :eligible, inclusion: { in: [true, false] }
  validates :allowed, :denied, inclusion: { in: JrcContactCenter::ModulePolicy::PERMISSIONS }
  validates :account_user_id, uniqueness: true, allow_nil: true
  validates :team_id, uniqueness: true, allow_nil: true
  validate :native_subject
  validate :team_attributes

  private

  def native_subject
    one_subject = account_user_id.present? != team_id.present?
    errors.add(:base, :invalid) unless one_subject
    subject = account_user || team
    errors.add(:account, :invalid) unless subject&.account_id == account_id
  end

  def team_attributes
    return if team_id.blank?

    errors.add(:base, :invalid) if eligible || denied.present?
  end
end
