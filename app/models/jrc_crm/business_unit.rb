# == Schema Information
#
# Table name: jrc_crm_business_units
#
#  id         :bigint           not null, primary key
#  active     :boolean          default(TRUE), not null
#  code       :string           not null
#  name       :string           not null
#  segment    :string
#  settings   :jsonb            not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  idx_jrc_crm_bu_account_code                 (account_id,code) UNIQUE
#  index_jrc_crm_business_units_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
module JrcCrm
  class BusinessUnit < ApplicationRecord
    self.table_name = 'jrc_crm_business_units'
    belongs_to :account
    has_many :user_business_units, class_name: 'JrcCrm::UserBusinessUnit', dependent: :destroy
    validates :name, :code, presence: true
    validates :code, uniqueness: { scope: :account_id }
  end
end
