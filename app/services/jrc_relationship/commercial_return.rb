class JrcRelationship::CommercialReturn
  def initialize(context, assignment)
    @context = context
    @assignment = assignment
    @customer = assignment.customer_context(context.member)
  end

  def call
    @context.records(JrcRelationship::ExpansionSignal).where(assignment: @assignment, status: 'converted').find_each do |signal|
      contracts = returned_contracts(signal)
      signal.with_lock do
        recorded = Array(signal.metadata['commercial_returns'])
        added = added_returns(signal, contracts, recorded)
        next if added.empty?

        signal.update!(metadata: signal.metadata.merge('commercial_returns' => recorded + added))
        @context.audit!(signal, after: { contract_ids: added.pluck('contract_id'), order_ids: added.pluck('order_id') },
                                action: 'expansion_contract_returned')
      end
    end
  end

  private

  def returned_contracts(signal)
    orders = @customer.orders.where(deal_id: signal.deal_id, order_origin: 'expansion').where.not(status: 'canceled')
    @customer.contracts.where(sales_order_id: orders.select(:id), deal_id: signal.deal_id,
                              status: %w[active expiring], signature_status: 'signed')
  end

  def added_returns(signal, contracts, recorded)
    contracts.includes(:contract_items, sales_order: :order_items).filter_map do |contract|
      next if recorded.any? { |entry| entry['contract_id'] == contract.id }

      ids = returned_products(contract)
      next if ids.empty? || (signal.product_id && ids.exclude?(signal.product_id))

      { 'contract_id' => contract.id, 'order_id' => contract.sales_order_id, 'deal_id' => signal.deal_id, 'product_ids' => ids,
        'monthly_cents' => contract.monthly_cents, 'captured_at' => Time.current.iso8601, 'actor_id' => @context.user.id }
    end
  end

  def returned_products(contract)
    ids = (contract.contract_items.where(status: 'active').pluck(:product_id) + contract.sales_order.order_items.pluck(:product_id)).compact.uniq
    @context.account.jrc_crm_products.active.where(id: ids).pluck(:id)
  end
end
