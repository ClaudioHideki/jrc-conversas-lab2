# == Schema Information
#
# Table name: jrc_crm_contract_templates
#
#  id          :bigint           not null, primary key
#  active      :boolean          default(TRUE), not null
#  body        :text             not null
#  category    :string
#  description :text
#  name        :string           not null
#  variables   :jsonb            not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  index_jrc_crm_contract_templates_on_account_id           (account_id)
#  index_jrc_crm_contract_templates_on_account_id_and_name  (account_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
module JrcCrm
  class ContractTemplate < ApplicationRecord
    self.table_name = 'jrc_crm_contract_templates'

    belongs_to :account
    has_many :contracts, class_name: 'JrcCrm::Contract', dependent: :nullify
    validates :name, :body, presence: true
    validates :name, uniqueness: { scope: :account_id }
  end
end
