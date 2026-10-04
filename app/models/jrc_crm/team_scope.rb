module JrcCrm
  class TeamScope < ApplicationRecord
    self.table_name = 'jrc_crm_team_scopes'

    SCOPES = %w[GROUP COMPANY BUSINESS_UNIT].freeze

    belongs_to :account
    belongs_to :team
    belongs_to :company, class_name: 'JrcCustomers::Company', optional: true
    belongs_to :business_unit, class_name: 'JrcCrm::BusinessUnit', optional: true

    validates :scope, inclusion: { in: SCOPES }
    validate :same_account
    validate :scope_shape

    scope :active, -> { where(active: true) }

    def covers?(company_id:, business_unit_id: nil)
      return true if scope == 'GROUP'
      return self.company_id == company_id if scope == 'COMPANY'

      scope == 'BUSINESS_UNIT' && self.business_unit_id == business_unit_id
    end

    private

    def same_account
      errors.add(:team, 'must belong to account') if team && team.account_id != account_id
      errors.add(:company, 'must belong to account') if company && company.account_id != account_id
      if company && company.has_attribute?(:relationship_type) && company.relationship_type != 'internal'
        errors.add(:company, 'must be an internal Company from the master directory')
      end
      errors.add(:company, 'must be active for an active scope') if active? && company&.respond_to?(:active?) && !company.active?
      errors.add(:business_unit, 'must belong to account') if business_unit && business_unit.account_id != account_id
      errors.add(:business_unit, 'must be active for an active scope') if active? && business_unit && !business_unit.active?
      return unless business_unit && company_id.present? && business_unit.company_id.present?

      errors.add(:business_unit, 'must belong to selected company') if business_unit.company_id != company_id
    end

    def scope_shape
      case scope
      when 'GROUP'
        errors.add(:company_id, 'must be blank for group scope') if company_id.present?
        errors.add(:business_unit_id, 'must be blank for group scope') if business_unit_id.present?
      when 'COMPANY'
        errors.add(:company_id, 'is required for company scope') if company_id.blank?
        errors.add(:business_unit_id, 'must be blank for company scope') if business_unit_id.present?
      when 'BUSINESS_UNIT'
        errors.add(:business_unit_id, 'is required for business unit scope') if business_unit_id.blank?
      end
    end
  end
end
