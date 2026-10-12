# frozen_string_literal: true

# Read-only companion to CommercialFinancials, not an approval policy or guard.
class JrcCrm::CommercialPriceEvaluation
  VERSION = 1
  ZERO_MINIMUM_MODES = %w[pending authorized_zero].freeze
  REFERENCE_FIELDS = %i[minimum_price_cents currency billing_model unit_name company_id business_unit_id price_table_id version].freeze

  def initialize(calculator:, attributes:, items:, currency:, zero_minimum:)
    @calculator = calculator
    @attributes = attributes
    @raw_items = items.map { |item| JrcCrm::CommercialFinancials.symbolize(item.to_h) }
    @currency = currency
    @zero_minimum = zero_minimum
    raise JrcCrm::CommercialFinancials::InvalidTerms, 'Invalid zero minimum mode.' unless ZERO_MINIMUM_MODES.include?(zero_minimum)
  end

  def call
    @issues = []
    return result([], nil) if missing_context?

    terms = @calculator.call
    weights = terms[:items].map { |item| item[:one_time_cents] - item[:snapshot][:setup_fee_cents] }
    eligible_weights = weights.each_with_index.map { |weight, index| eligible?(@raw_items[index]) ? weight : 0 }
    discount = terms[:discount_cents]
    if discount > eligible_weights.sum
      @issues << { code: 'global_discount_exceeds_eligible_base' }
      return result([], terms)
    end
    if @attributes[:discount_cents] && !@attributes.dig(:snapshot, :discount_percent) &&
       JrcCrm::CommercialFinancials.money(@attributes[:discount_cents]) > terms[:products_cents]
      @issues << { code: 'global_discount_capped_by_legacy_valuation' }
    end
    shares = JrcCrm::CommercialFinancials.allocate(discount, eligible_weights)
    rows = terms[:items].each_with_index.map { |item, index| evaluate_item(item, index, weights[index], shares[index]) }
    result(rows, terms)
  end

  private

  def missing_context?
    @issues << { code: 'document_currency_required' } unless @currency.is_a?(String) && @currency.match?(/\A[A-Z]{3}\z/)
    @issues << { code: 'item_breakdown_required' } if @raw_items.empty?
    @raw_items.each_with_index do |item, index|
      currencies = [item[:currency], item.dig(:snapshot, :currency)].compact
      if currencies.any? { |currency| currency != @currency }
        @issues << { code: 'mixed_document_currency', item_index: index }
      end
      price = item.fetch(:unit_cents, item[:unit_price_cents])
      if price.nil? || price == ''
        @issues << { code: 'item_price_required', item_index: index }
      end
    end
    @issues.any?
  end

  def eligible?(item)
    value = item.fetch(:eligible_for_global_discount, true)
    raise JrcCrm::CommercialFinancials::InvalidTerms, 'Discount eligibility must be boolean.' unless [true, false].include?(value)

    value
  end

  def evaluate_item(item, index, net_before_global, share)
    raw = @raw_items[index]
    gross = (item[:quantity] * item[:unit_cents]).round(0, BigDecimal::ROUND_HALF_UP).to_i
    net = net_before_global - share
    effective = Rational(net) / item[:quantity].to_r
    issues = []
    if !raw.key?(:discount_percent) && JrcCrm::CommercialFinancials.money(raw[:discount_cents]) > gross
      issues << 'item_discount_capped_by_legacy_valuation'
    end
    reference = JrcCrm::CommercialFinancials.symbolize((raw[:price_reference] || raw.dig(:snapshot, :price_reference) || {}).to_h)
    reference = reference.slice(*REFERENCE_FIELDS)
    minimum = reference[:minimum_price_cents]
    issues << 'minimum_price_required' if minimum.nil?
    minimum = integer_cents(minimum) unless minimum.nil?
    issues << 'zero_minimum_policy_required' if minimum == 0 && @zero_minimum == 'pending'
    issues << 'minimum_currency_required' unless reference[:currency].is_a?(String) && reference[:currency].match?(/\A[A-Z]{3}\z/)
    issues << 'minimum_currency_mismatch' if reference[:currency] && reference[:currency] != @currency
    billing = raw[:billing_model] || raw.dig(:snapshot, :billing_model)
    issues << 'item_billing_model_required' unless JrcCrm::CommercialFinancials::BILLING_MODELS.include?(billing)
    issues << 'minimum_billing_model_required' unless JrcCrm::CommercialFinancials::BILLING_MODELS.include?(reference[:billing_model])
    issues << 'billing_model_mismatch' if billing && reference[:billing_model] && billing != reference[:billing_model]
    unit = raw[:unit_name] || raw.dig(:snapshot, :unit_name)
    units = [unit, reference[:unit_name]]
    issues << 'price_unit_required' unless units.all? { |value| value.is_a?(String) && !value.strip.empty? }
    issues << 'price_unit_mismatch' if unit && reference[:unit_name] && unit != reference[:unit_name]
    comparison = if issues.empty?
                   { -1 => 'below', 0 => 'equal', 1 => 'above' }.fetch(effective <=> minimum)
                 else
                   'pending'
                 end
    issues.each { |code| @issues << { code: code, item_index: index } }
    {
      item_index: index, product_id: item[:product_id], quantity: item[:quantity].to_s('F'),
      currency: @currency, billing_model: billing, unit_name: unit, gross_line_cents: gross,
      item_discount_cents: item[:discount_cents], global_discount_cents: share,
      setup_fee_cents: item[:snapshot][:setup_fee_cents], effective_line_cents: net,
      effective_unit_cents: { numerator: effective.numerator, denominator: effective.denominator },
      minimum_price_cents: minimum, comparison: comparison, issues: issues,
      price_reference: reference.dup
    }
  end

  def integer_cents(value)
    amount = BigDecimal(value.to_s)
    unless amount.finite? && amount >= 0 && amount == amount.round(0)
      raise JrcCrm::CommercialFinancials::InvalidTerms, 'Minimum must be nonnegative integer cents.'
    end
    amount.to_i
  rescue ArgumentError => e
    raise e if e.is_a?(JrcCrm::CommercialFinancials::InvalidTerms)

    raise JrcCrm::CommercialFinancials::InvalidTerms, 'Invalid minimum price.'
  end

  def result(items, financials)
    {
      price_evaluation_version: VERSION, status: @issues.empty? ? 'evaluated' : 'pending',
      currency: @currency, basis: 'net_line_excluding_setup_shipping_taxes',
      allocation: 'largest_remainder_net_eligible_lines_input_order_ties',
      zero_minimum_mode: @zero_minimum, items: items, issues: @issues,
      below_minimum_item_indexes: items.select { |item| item[:comparison] == 'below' }.map { |item| item[:item_index] },
      financials: financials
    }
  end
end
