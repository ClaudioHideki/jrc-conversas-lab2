# == Schema Information
#
# Table name: jrc_crm_deal_products
#
#  id                   :bigint           not null, primary key
#  description_snapshot :text
#  discount_cents       :bigint           default(0)
#  notes                :text
#  quantity             :integer          default(1)
#  total_cents          :bigint
#  unit_price_cents     :bigint
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  deal_id              :bigint
#  product_id           :bigint
#
# Indexes
#
#  index_jrc_crm_deal_products_on_deal_id     (deal_id)
#  index_jrc_crm_deal_products_on_product_id  (product_id)
#
# Foreign Keys
#
#  fk_rails_...  (deal_id => jrc_crm_deals.id)
#  fk_rails_...  (product_id => jrc_crm_products.id)
#
module JrcCrm
  class DealProduct < ApplicationRecord
    self.table_name = 'jrc_crm_deal_products'
    include JrcCrm::CommercialGratuityIntent

    belongs_to :deal, class_name: 'JrcCrm::Deal'
    belongs_to :product, class_name: 'JrcCrm::Product', optional: true

    validates :quantity, numericality: { greater_than: 0 }
    validates :unit_price_cents, numericality: { greater_than_or_equal_to: 0 }

    before_validation :calculate_total

    private

    def calculate_total
      return unless unit_price_cents && quantity
      self.total_cents = [(unit_price_cents * quantity) - (discount_cents || 0), 0].max
    end
  end
end
