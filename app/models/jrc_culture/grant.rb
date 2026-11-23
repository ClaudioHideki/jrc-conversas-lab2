# frozen_string_literal: true

class JrcCulture::Grant < ApplicationRecord
  self.table_name = 'jrc_culture_grants'

  belongs_to :account
  belongs_to :account_user, optional: true
  belongs_to :unit, class_name: 'JrcCrm::BusinessUnit'
  has_many :participations, class_name: 'JrcCulture::Participation', dependent: :restrict_with_exception

  scope :live, lambda {
    joins(:account_user, unit: :operating_company)
      .where(active: true, jrc_crm_business_units: { active: true }, companies: { active: true, relationship_type: 'internal' })
      .where('account_users.account_id = jrc_culture_grants.account_id AND account_users.user_id = jrc_culture_grants.user_key')
  }

  scope :eligible, lambda {
    live.where(<<~SQL.squish)
      EXISTS (
        SELECT 1 FROM jrc_crm_user_business_units coverage
        WHERE coverage.account_id = jrc_culture_grants.account_id
          AND coverage.user_id = jrc_culture_grants.user_key
          AND coverage.active AND coverage.structure_managed
          AND (
            coverage.scope = 'GROUP'
            OR (coverage.scope = 'COMPANY' AND coverage.company_id = jrc_crm_business_units.company_id)
            OR (coverage.scope = 'BUSINESS_UNIT' AND coverage.business_unit_id = jrc_culture_grants.unit_id)
          )
      )
    SQL
  }

  validates :role, inclusion: { in: %w[employee administrator] }
  validates :department, length: { maximum: 120 }
  attr_readonly :account_id, :account_user_id, :unit_id, :member_key, :user_key, :role
  before_validation :snapshot_identity, on: :create
  validate :same_scope, on: :create

  private

  def snapshot_identity
    self.member_key = account_user&.id
    self.user_key = account_user&.user_id
  end

  def same_scope
    return if account_user&.account_id == account_id && unit&.account_id == account_id && unit&.operating_company&.account_id == account_id &&
              unit.operating_company.relationship_type == 'internal'

    errors.add(:base, :invalid)
  end
end
