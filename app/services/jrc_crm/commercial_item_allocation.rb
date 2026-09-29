module JrcCrm
  # Product-scoped revenue is the eligible items' net initial amount, with the
  # order-level discount allocated proportionally. Freight/taxes are not products.
  class CommercialItemAllocation
    def self.call(items:, discount_cents: 0, monthly_enabled: true)
      rows = items.map { |item| CommercialFinancials.symbolize(item.respond_to?(:attributes) ? item.attributes : item.to_h) }
      weights = rows.map { |row| CommercialFinancials.money(row[:one_time_cents]) }
      discount = [CommercialFinancials.money(discount_cents), weights.sum].min
      discounts = CommercialFinancials.allocate(discount, weights)
      rows.each_with_index.map do |row, index|
        { product_id: row[:product_id], quantity: BigDecimal((row[:quantity] || 0).to_s),
          revenue_cents: weights[index] - discounts[index],
          monthly_cents: monthly_enabled ? CommercialFinancials.money(row[:recurring_cents]) : 0 }
      end
    end
  end
end
