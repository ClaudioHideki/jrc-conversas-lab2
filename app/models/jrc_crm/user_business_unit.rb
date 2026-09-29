# == Schema Information
#
# Table name: jrc_crm_user_business_units
#
#  id               :bigint           not null, primary key
#  permissions      :jsonb            not null
#  scope            :string           default("OWN"), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  business_unit_id :bigint           not null
#  user_id          :bigint           not null
#
# Indexes
#
#  idx_jrc_crm_user_bu_unique                             (business_unit_id,user_id) UNIQUE
#  index_jrc_crm_user_business_units_on_account_id        (account_id)
#  index_jrc_crm_user_business_units_on_business_unit_id  (business_unit_id)
#  index_jrc_crm_user_business_units_on_user_id           (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (business_unit_id => jrc_crm_business_units.id)
#  fk_rails_...  (user_id => users.id)
#
module JrcCrm
  class UserBusinessUnit < ApplicationRecord
    self.table_name = 'jrc_crm_user_business_units'
    SCOPES = %w[OWN TEAM BUSINESS_UNIT SELECTED_BUSINESS_UNITS GROUP].freeze
    belongs_to :account
    belongs_to :business_unit, class_name: 'JrcCrm::BusinessUnit'
    belongs_to :user
    validates :scope, inclusion: { in: SCOPES }
    validate :same_account

    private

    def same_account
      errors.add(:business_unit, 'must belong to account') if business_unit && business_unit.account_id != account_id
      errors.add(:user, 'must belong to account') if user && !account.users.exists?(user.id)
    end
  end
end
