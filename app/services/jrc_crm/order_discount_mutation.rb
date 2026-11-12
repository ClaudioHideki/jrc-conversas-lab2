# Bounded price mutation for an uncommitted order. Uses the same financial
# calculator, storage projection, corporate scope and invalidation as native
# order edits. It does not approve the order or run fulfillment/downstream jobs.
class JrcCrm::OrderDiscountMutation
  def self.authorize!(order, actor)
    account = order.account.reload
    member = account.account_users.includes(:user).find_by(user_id: actor&.id)
    raise Pundit::NotAuthorizedError unless member && account.active? && account.feature_enabled?('jrc_crm') &&
      member.user.active_for_authentication? && member.permissions.include?('jrc_crm')

    rows = JrcCrm::SalesOrder.where(account_id: account.id, id: order.id)
    rows = rows.where(owner_id: actor.id) unless member.administrator?
    visibility = JrcCrm::OrganizationalVisibility.new(account: account, user: actor, relation: rows)
    raise Pundit::NotAuthorizedError unless visibility.call.exists?

    JrcCrm::CorporateIssuer.authorize_resource!(order, actor)
  end

  def self.locked?(order)
    !JrcApprovals::AdjustmentSources.order_mutable?(status: order.status,
      terms_locked: order.commercial_terms_locked?, invoiced: order.invoices.exists?)
  end

  def self.call!(order:, actor:, attributes:)
    amount = JrcApprovals::AdjustmentSources.discount!(attributes)
    order.with_lock do
      authorize!(order, actor)
      raise JrcApprovals::Error, 'SOURCE_LOCKED' if locked?(order)

      before = order.attributes.slice('discount_cents', 'total_cents', 'monthly_cents')
      # Monetary entry is explicit. Do not let an old percent override the new
      # integer amount; snapshot_for is the native monetary projection.
      snapshot = (order.snapshot || {}).deep_dup.merge('discount_percent' => nil)
      result = JrcCrm::OrderFinancials.new(attributes: order.attributes.merge(attributes).merge('snapshot' => snapshot),
        items: order.order_items.order(:id).map(&:attributes)).call
      raise JrcApprovals::Error, 'INVALID_COMMERCIAL_TERMS' unless result.fetch(:discount_cents) == amount

      order.assign_attributes(JrcCrm::OrderFinancials.attributes_for(result))
      order.snapshot = JrcCrm::OrderFinancials.snapshot_for(result, snapshot)
      order.save!
      JrcApprovals::CommercialInvalidation.call(resource: order.reload, user: actor)
      JrcCrm::AuditEvent.create!(account: order.account, actor_type: 'User', actor_id: actor.id,
        event_type: 'order_updated', resource_type: order.class.name, resource_id: order.id,
        from_value: before, to_value: order.attributes.slice(*before.keys),
        metadata: { source: 'native_approval_discount_adjustment' })
      authorize!(order, actor)
      order.reload
    end
  end
end
