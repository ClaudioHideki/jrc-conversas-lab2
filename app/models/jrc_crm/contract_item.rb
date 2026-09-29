# == Schema Information
#
# Table name: jrc_crm_contract_items
#
#  id                     :bigint           not null, primary key
#  monthly_cents          :bigint           default(0), not null
#  name                   :string           not null
#  one_time_cents         :bigint           default(0), not null
#  operational_identifier :string
#  quantity               :decimal(14, 3)   default(1.0), not null
#  snapshot               :jsonb            not null
#  starts_on              :date
#  status                 :string           default("pending"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  contract_id            :bigint           not null
#  product_id             :bigint
#
# Indexes
#
#  index_jrc_crm_contract_items_on_contract_id  (contract_id)
#  index_jrc_crm_contract_items_on_product_id   (product_id)
#
# Foreign Keys
#
#  fk_rails_...  (contract_id => jrc_crm_contracts.id)
#  fk_rails_...  (product_id => jrc_crm_products.id)
#
module JrcCrm
  class ContractItem < ApplicationRecord
    self.table_name = 'jrc_crm_contract_items'
    belongs_to :contract, class_name: 'JrcCrm::Contract'
    belongs_to :product, class_name: 'JrcCrm::Product', optional: true
    validates :name, presence: true
  end
end
