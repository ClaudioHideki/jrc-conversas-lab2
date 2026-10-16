# One native snapshot contract shared by proposal creation, editing and valuation inputs.
class JrcCrm::CommercialProductSnapshot
  FIELDS = %i[billing_model setup_fee_cents included_quantity included_unit overage_unit_price_cents activation_days validation_period_days].freeze
  DEFAULTS = { billing_model: 'one_time', setup_fee_cents: 0, included_quantity: 0, included_unit: nil,
               overage_unit_price_cents: 0, activation_days: 0, validation_period_days: 0 }.freeze

  def self.from_product(product, intent: {})
    data = DEFAULTS.merge(product ? product.attributes.symbolize_keys.slice(*FIELDS) : {})
    data[:unit_name] = product&.sales_unit.presence || 'unidade'
    data[:setup_fee_cents] = 0 if intent.to_h.stringify_keys['type'] == 'installation'
    data
  end

  def self.from_item(item)
    data = item.attributes.symbolize_keys.slice(*FIELDS, :unit_name)
    data[:description] = item.description_snapshot
    data[:commercial_gratuity] = item.commercial_gratuity.deep_dup if item.commercial_gratuity.present?
    data
  end
end
