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
    validate :preserve_corporate_issuer
    validate :service_desk_link_is_consistent

    scope :active, -> { where(active: true) }
    scope :ordered, -> { order(:name, :id) }

    private

    def service_desk_link_is_consistent
      return unless settings.is_a?(Hash) && settings.key?('service_desk_unit_id')

      value = settings['service_desk_unit_id']
      valid = value.is_a?(String) && value.match?(/\A[1-9]\d*\z/) &&
              JrcServiceDesk::Unit.where(account_id: account_id).exists?(id: value)
      errors.add(:settings, 'must reference a Service Desk unit from this account') unless valid
      linked = self.class.where(account_id: account_id).where("settings ->> 'service_desk_unit_id' = ?", value.to_s).where.not(id: id)
      errors.add(:settings, 'Service Desk unit already belongs to another business unit') if linked.exists?
    end

    def preserve_corporate_issuer
      return unless persisted? && company_id_in_database && will_save_change_to_company_id?

      errors.add(:operating_company, 'cannot replace an established corporate issuer')
    end

    def operating_company_belongs_to_account
      return unless operating_company

      errors.add(:operating_company, 'must belong to account') if operating_company.account_id != account_id
      if active? && operating_company.respond_to?(:active?) && !operating_company.active?
        errors.add(:operating_company,
                   'must be active for an active business unit')
      end
      return unless operating_company.has_attribute?(:relationship_type) && operating_company.relationship_type != 'internal'

      errors.add(:operating_company, 'must use an internal Company from the master directory')
    end
  end
end
