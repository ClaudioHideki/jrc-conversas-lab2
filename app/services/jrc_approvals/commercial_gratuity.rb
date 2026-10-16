# Read-only commercial classification; never a valuation replacement or an approval.
class JrcApprovals::CommercialGratuity
  VERSION = 1
  TYPES = JrcCrm::CommercialGratuityIntent::TYPES

  def initialize(resource:, context: nil)
    @resource = resource
    @context = context || JrcApprovals::NativePriceContext.new(resource).call
  end

  def call
    entries = evidence
    { has_commercial_gratuity: entries.any?, gratuity_item_count: entries.pluck(:item_index).uniq.length,
      gratuity_type: entries.pluck(:type).uniq.sort,
      gratuity_total_cents: entries.sum { |row| row[:reference_cents] }, below_minimum_total_cents: below_minimum_total,
      discount_percentage: discount_percentage,
      gratuity_value_status: entries.any? { |row| row[:reference_cents].zero? } ? 'pending' : 'evaluated',
      approval_context_version: VERSION, evidence: entries }
  end

  private

  def evidence
    items = @context[:valuation][:items]
    weights = items.map { |row| row[:one_time_cents] - row[:snapshot][:setup_fee_cents] }
    shares = JrcCrm::CommercialFinancials.allocate([@context[:valuation][:discount_cents], weights.sum].min, weights)
    source_items.each_with_index.flat_map do |item, index|
      JrcApprovals::GratuityLine.new(item: item, valued: items[index], share: shares[index], index: index, account_id: @resource.account_id).call
    end
  end

  def below_minimum_total
    @context[:evaluation][:items].select { |row| row[:comparison] == 'below' }.sum do |row|
      ((BigDecimal(row[:quantity]).to_r * row[:minimum_price_cents]) - row[:effective_line_cents]).ceil
    end
  end

  def discount_percentage
    items = @context[:valuation][:items]
    gross = items.sum { |row| (row[:quantity] * row[:unit_cents]).round.to_i }
    return '0.0' unless gross.positive?

    discount = items.sum { |row| row[:discount_cents] } + @context[:valuation][:discount_cents]
    (BigDecimal(discount.to_s) * 100 / gross).round(6).to_s('F')
  end

  def source_items
    return @resource.proposal_items.order(:id).to_a if @resource.is_a?(JrcCrm::Proposal)
    return @resource.deal_products.order(:id).to_a if @resource.is_a?(JrcCrm::Deal)

    @resource.order_items.order(:id).to_a
  end
end
