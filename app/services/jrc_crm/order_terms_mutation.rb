# Bounded native order financial recalculation. No activation, invoice or provider call.
class JrcCrm::OrderTermsMutation
  def self.call!(order:, actor:, attributes:)
    allowed = JrcApprovals::AdjustmentPolicy::SOURCES.fetch('crm.order_terms')
    raise JrcApprovals::Error, 'INVALID_ADJUSTMENT_FIELDS' unless attributes.any? && (attributes.keys - allowed).empty?
    order.with_lock do
      JrcCrm::OrderDiscountMutation.authorize!(order, actor)
      raise JrcApprovals::Error, 'SOURCE_LOCKED' if JrcCrm::OrderDiscountMutation.locked?(order)
      before = JrcApprovals::FinancialCatalog.values(order).slice(*attributes.keys)
      snapshot = order.snapshot.to_h.deep_dup
      snapshot['first_due_date'] = attributes['first_due_date'] if attributes.key?('first_due_date')
      stored = attributes.except('first_due_date')
      result = JrcCrm::OrderFinancials.new(attributes: order.attributes.merge(stored).merge('snapshot' => snapshot),
        items: order.order_items.order(:id).map(&:attributes)).call
      order.assign_attributes(stored.merge(JrcCrm::OrderFinancials.attributes_for(result)))
      order.snapshot = JrcCrm::OrderFinancials.snapshot_for(result, snapshot)
      order.save!
      JrcCrm::OrderDiscountMutation.authorize!(order, actor)
      JrcApprovals::CommercialInvalidation.call(resource: order.reload, user: actor)
      JrcCrm::AuditEvent.create!(account: order.account, actor_type: 'User', actor_id: actor.id,
        event_type: 'order_updated', resource_type: order.class.name, resource_id: order.id,
        from_value: before, to_value: JrcApprovals::FinancialCatalog.values(order).slice(*attributes.keys),
        metadata: { source: 'native_approval_financial_adjustment' })
      order
    end
  end
end
