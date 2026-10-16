# Classification of one persisted item, using its native product and settled price evaluation.
class JrcApprovals::GratuityLine
  def initialize(item:, valued:, share:, index:, account_id:)
    @item = item
    @valued = valued
    @share = share
    @index = index
    @product = JrcCrm::Product.where(account_id: account_id).find_by(id: item.product_id)
  end

  def call
    return [] unless @valued

    @intent = intent!
    [setup_evidence, line_evidence].compact
  end

  private

  def intent!
    data = @item.respond_to?(:commercial_gratuity) ? @item.commercial_gratuity : @item.snapshot.fetch('commercial_gratuity', {})
    raise JrcApprovals::Error, 'INVALID_GRATUITY_INTENT' unless JrcCrm::CommercialGratuityIntent.valid_payload?(data)

    data
  end

  def setup_evidence
    return unless @valued[:snapshot][:setup_fee_cents].to_i.zero?

    cents = @product&.setup_fee_cents.to_i
    return unless cents.positive? || @intent['type'] == 'installation'

    evidence('installation', cents)
  end

  def line_evidence
    net = @valued[:one_time_cents] - @valued[:snapshot][:setup_fee_cents].to_i - @share.to_i
    return unless net.zero?

    declared = @intent['type'].presence unless @intent['type'] == 'installation'
    cents = @product&.unit_price_cents.to_i
    return unless cents.positive? || declared

    evidence(declared || default_type, (@valued[:quantity] * cents).round.to_i)
  end

  def default_type
    return 'monthly_fee' if %w[monthly annual usage].include?(@valued[:snapshot][:billing_model])

    @product&.product_type == 'product' ? 'product' : 'service'
  end

  def evidence(type, cents)
    { item_index: @index, type: type, reference_cents: cents, declaration: @intent.deep_dup }
  end
end
