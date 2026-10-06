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
    validate :valid_selection_rules

    def valid_selection_rules
      if !selection_rules.is_a?(Hash) || (selection_rules.keys - JrcCrm::ContractTemplateSelection::KEYS).any?
        errors.add(:selection_rules, 'critérios comerciais inválidos')
      end
      return unless selection_rules.is_a?(Hash)
      if selection_rules['operating_company_id'].present? && !JrcCustomers::Company.where(account_id: account_id).exists?(selection_rules['operating_company_id'])
        errors.add(:selection_rules, 'empresa operadora deve pertencer à conta')
      end
      if (Array(selection_rules['product_ids']).map(&:to_i) - account.jrc_crm_products.where(id: selection_rules['product_ids']).pluck(:id)).any?
        errors.add(:selection_rules, 'produtos devem pertencer à conta')
      end
    end
  end
end
