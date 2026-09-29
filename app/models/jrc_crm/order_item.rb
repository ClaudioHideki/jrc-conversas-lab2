# == Schema Information
#
# Table name: jrc_crm_order_items
#
#  id              :bigint           not null, primary key
#  discount_cents  :bigint           default(0), not null
#  name            :string           not null
#  one_time_cents  :bigint           default(0), not null
#  quantity        :decimal(14, 3)   default(1.0), not null
#  recurring_cents :bigint           default(0), not null
#  snapshot        :jsonb            not null
#  unit_cents      :bigint           default(0), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  product_id      :bigint
#  sales_order_id  :bigint           not null
#
# Indexes
#
#  index_jrc_crm_order_items_on_product_id      (product_id)
#  index_jrc_crm_order_items_on_sales_order_id  (sales_order_id)
#
# Foreign Keys
#
#  fk_rails_...  (product_id => jrc_crm_products.id)
#  fk_rails_...  (sales_order_id => jrc_crm_sales_orders.id)
#
module JrcCrm
  class OrderItem < ApplicationRecord
    self.table_name = 'jrc_crm_order_items'
    belongs_to :sales_order, class_name: 'JrcCrm::SalesOrder'
    belongs_to :product, class_name: 'JrcCrm::Product', optional: true
    validates :name, presence: true
    validates :quantity, numericality: { greater_than: 0 }
    validates :unit_cents, :discount_cents, :one_time_cents, :recurring_cents,
              numericality: { greater_than_or_equal_to: 0 }
    validate :product_belongs_to_order_account

    def product_belongs_to_order_account
      errors.add(:product, 'must belong to account') if product && sales_order && product.account_id != sales_order.account_id
    end
  end
end
