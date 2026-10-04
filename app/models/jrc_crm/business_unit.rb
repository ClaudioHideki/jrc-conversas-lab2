# == Schema Information
#
# Table name: jrc_crm_business_units
#
module JrcCrm
  class BusinessUnit < ApplicationRecord
    self.table_name = 'jrc_crm_business_units'

    belongs_to :account
    belongs_to :operating_company, class_name: 'JrcCustomers::Company', foreign_key: :company_id, optional: true
    has_many :user_business_units, class_name: 'JrcCrm::UserBusinessUnit', dependent: :destroy
    has_many :team_scopes, class_name: 'JrcCrm::TeamScope', dependent: :restrict_with_error

    validates :name, :code, presence: true
    validates :code, uniqueness: { scope: :account_id }
    validate :operating_company_belongs_to_account

    scope :active, -> { where(active: true) }
    scope :ordered, -> { order(:name, :id) }

    private

    def operating_company_belongs_to_account
      return unless operating_company

      errors.add(:operating_company, 'must belong to account') if operating_company.account_id != account_id
      errors.add(:operating_company, 'must be active for an active business unit') if active? && operating_company.respond_to?(:active?) && !operating_company.active?
      if operating_company.has_attribute?(:relationship_type) && operating_company.relationship_type != 'internal'
        errors.add(:operating_company, 'must use an internal Company from the master directory')
      end
    end
  end
end
