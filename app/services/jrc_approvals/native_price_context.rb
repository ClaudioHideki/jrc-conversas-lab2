# Reads native product references, replacing every client-supplied price_reference.
class JrcApprovals::NativePriceContext
  def initialize(resource)
    @resource = resource
    @unit = JrcApprovals::CommercialCatalog.business_unit(resource)
  end

  def call
    proposal = @resource.is_a?(JrcCrm::Proposal)
    deal = @resource.is_a?(JrcCrm::Deal)
    rows = if deal
             @resource.deal_products.order(:id).map do |item|
               { product_id: item.product_id, quantity: item.quantity, unit_cents: item.unit_price_cents,
                 discount_cents: item.discount_cents, snapshot: {} }
             end
           elsif proposal
             @resource.proposal_items.order(:id).map do |item|
               { product_id: item.product_id, name: item.name_snapshot, quantity: item.quantity,
                 unit_cents: item.unit_price_cents, discount_cents: item.discount_cents,
                 snapshot: item.attributes.slice('billing_model', 'unit_name', 'setup_fee_cents') }
             end
           else
             @resource.order_items.order(:id).map do |item|
               item.attributes.slice('product_id', 'name', 'quantity', 'unit_cents', 'discount_cents', 'snapshot')
             end
           end
    rows = rows.map(&:deep_symbolize_keys)
    products = JrcCrm::Product.where(account_id: @resource.account_id, id: rows.map { |row| row[:product_id] }).index_by(&:id)
    currencies = products.values.map(&:currency).uniq
    # Native item currencies must explicitly agree. No conversion or BRL fallback.
    document_deal = deal ? @resource : @resource.deal
    currency = document_deal&.currency.presence || (@resource.is_a?(JrcCrm::SalesOrder) && @resource.snapshot['currency'].presence) ||
      (currencies.one? ? currencies.first : nil)
    references = rows.map do |row|
      product = products[row[:product_id]]
      if deal
        row[:snapshot] = { billing_model: product&.billing_model, unit_name: product&.sales_unit,
                           setup_fee_cents: product&.setup_fee_cents }
      end
      row.delete(:price_reference)
      row[:snapshot] = row.fetch(:snapshot, {}).except(:price_reference, :eligible_for_global_discount)
      row[:currency] = product&.currency
      reference = product && product.active? ? {
        minimum_price_cents: product.minimum_price_cents, currency: product.currency,
        billing_model: product.billing_model, unit_name: product.sales_unit,
        company_id: @unit&.company_id, business_unit_id: @unit&.id,
        version: product.updated_at.getutc.iso8601(6)
      } : {}
      row[:price_reference] = reference
      { product_id: row[:product_id], active: product&.active?, reference: reference }
    end
    attrs = @resource.attributes.slice('discount_cents', 'shipping_cents', 'shipping_mode', 'shipping_in_installments',
      'payment_condition', 'payment_method', 'down_payment_cents', 'installments_count', 'has_monthly_fee', 'taxes_included',
      'issuer_company_name', 'issuer_tax_id', 'issuer_unit', 'first_billing_days', 'term_months', 'annual_adjustment_index', 'renewal_type')
    # Persisted OrderFinancials stores percent discounts as settled cents. Do not trust authorization metadata in snapshot.
    if !proposal && !deal
      attrs['snapshot'] = @resource.snapshot.to_h.slice('shipping_mode', 'shipping_in_installments', 'taxes_cents',
        'taxes_percent', 'has_monthly_fee', 'first_due_date')
    end
    calculator = JrcCrm::CommercialFinancials.new(attributes: attrs.merge('currency' => currency), items: rows)
    evaluation = calculator.evaluate_prices
    { evaluation: evaluation, valuation: evaluation[:financials] || calculator.call, fingerprint_data: {
      attributes: attrs, items: rows, references: references,
      customer_id: proposal ? @resource.customer_contact&.id : @resource.contact_id,
      customer_company_id: proposal ? @resource.customer_company&.id : @resource.contact&.company_id,
      deal_id: document_deal&.id, unit_id: @unit&.id
    } }
  end
end
