# Existing table evolved into the per-user organizational coverage store.
# The permissions JSON column is retained for backward compatibility only;
# functional permissions continue to come from native roles/custom roles.
module JrcCrm
  class UserBusinessUnit < ApplicationRecord
    self.table_name = 'jrc_crm_user_business_units'

    LEGACY_SCOPES = %w[OWN TEAM SELECTED_BUSINESS_UNITS].freeze
    STRUCTURE_SCOPES = %w[GROUP COMPANY BUSINESS_UNIT].freeze
    SCOPES = (LEGACY_SCOPES + STRUCTURE_SCOPES).freeze

    belongs_to :account
    belongs_to :business_unit, class_name: 'JrcCrm::BusinessUnit', optional: true
    belongs_to :company, class_name: 'JrcCustomers::Company', optional: true
    belongs_to :team, optional: true
    belongs_to :user

    validates :scope, inclusion: { in: SCOPES }
    validate :same_account
    validate :structure_scope_shape, if: :structure_managed?
    validate :team_membership, if: -> { structure_managed? && team_id.present? }
    validate :covered_by_team, if: -> { structure_managed? && team_id.present? }
    validate :no_duplicate_structure_scope, if: :structure_managed?

    scope :active, -> { where(active: true) }
    scope :structure_managed, -> { where(structure_managed: true) }

    private

    def same_account
      errors.add(:business_unit, 'must belong to account') if business_unit && business_unit.account_id != account_id
      errors.add(:business_unit, 'must be active for an active scope') if active? && business_unit && !business_unit.active?
      errors.add(:company, 'must belong to account') if company && company.account_id != account_id
      if company && company.has_attribute?(:relationship_type) && company.relationship_type != 'internal'
        errors.add(:company, 'must be an internal Company from the master directory')
      end
      errors.add(:company, 'must be active for an active scope') if active? && company&.respond_to?(:active?) && !company.active?
      errors.add(:team, 'must belong to account') if team && team.account_id != account_id
      errors.add(:user, 'must belong to account') if user && !account.users.exists?(id: user.id)
      return unless business_unit && company_id.present? && business_unit.company_id.present?

      errors.add(:business_unit, 'must belong to selected company') if business_unit.company_id != company_id
    end

    def structure_scope_shape
      case scope
      when 'GROUP'
        errors.add(:company_id, 'must be blank for group scope') if company_id.present?
        errors.add(:business_unit_id, 'must be blank for group scope') if business_unit_id.present?
      when 'COMPANY'
        errors.add(:company_id, 'is required for company scope') if company_id.blank?
        errors.add(:business_unit_id, 'must be blank for company scope') if business_unit_id.present?
      when 'BUSINESS_UNIT'
        errors.add(:business_unit_id, 'is required for business unit scope') if business_unit_id.blank?
      else
        errors.add(:scope, 'is not a structure-managed scope')
      end
    end

    def team_membership
      errors.add(:team, 'user must belong to the selected department/team') unless team.members.exists?(id: user_id)
    end

    def covered_by_team
      scopes = JrcCrm::TeamScope.active.where(account_id: account_id, team_id: team_id)
      company_key = company_id || business_unit&.company_id
      return if scopes.any? { |candidate| candidate.covers?(company_id: company_key, business_unit_id: business_unit_id) }

      errors.add(:base, 'user coverage must stay inside the selected department/team coverage')
    end

    def no_duplicate_structure_scope
      relation = self.class.structure_managed.where(account_id: account_id, user_id: user_id, team_id: team_id, scope: scope,
                                                     company_id: company_id, business_unit_id: business_unit_id, active: true)
      relation = relation.where.not(id: id) if persisted?
      errors.add(:base, 'duplicate active user coverage') if active? && relation.exists?
    end
  end
end
