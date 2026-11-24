# frozen_string_literal: true

class JrcCulture::Grant < ApplicationRecord
  self.table_name = 'jrc_culture_grants'

  belongs_to :account
  belongs_to :account_user, optional: true
  belongs_to :unit, class_name: 'JrcCrm::BusinessUnit', optional: true
  has_many :participations, class_name: 'JrcCulture::Participation', dependent: :restrict_with_exception

  scope :live, lambda {
    joins(:account_user).where(active: true)
      .where('account_users.account_id = jrc_culture_grants.account_id AND account_users.user_id = jrc_culture_grants.user_key')
  }

  scope :eligible, lambda {
    base = live.left_joins(unit: :operating_company)
    account_grants = base.where(unit_id: nil, account_id: account_level_accounts.select(:id))
    unit_grants = base.where(jrc_crm_business_units: { active: true }, companies: { active: true, relationship_type: 'internal' })
    unit_grants = unit_grants.where(<<~SQL.squish)
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
    account_grants.or(unit_grants)
  }

  def self.account_level_accounts
    linked = JrcCrm::BusinessUnit.where.not(company_id: nil).where.not(account_id: nil)
    Account.where.not(id: linked.select(:account_id))
  end

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
    valid_unit = if unit_id.nil?
                   self.class.account_level_accounts.exists?(id: account_id)
                 else
                   unit&.account_id == account_id && unit&.operating_company&.account_id == account_id &&
                     unit.operating_company.relationship_type == 'internal'
                 end
    return if account_user&.account_id == account_id && valid_unit

    errors.add(:base, :invalid)
  end
end
