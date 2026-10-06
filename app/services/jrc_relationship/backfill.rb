class JrcRelationship::Backfill
  def initialize(context:)
    @context = context
    raise Pundit::NotAuthorizedError unless context.policy.admin?
  end

  # Dry-run is the default. No customer, contact, order or contract is created.
  def call(apply: false)
    report = { account_id: @context.account.id, applied: apply, scanned: 0, eligible: 0, created: 0, existing: 0,
               excluded: Hash.new(0), excluded_orders: [], orders: [], authorized_assignments: @context.assignments.count,
               unassigned: @context.assignments.where(owner_id: nil).count,
               flags: { relationship: @context.account.feature_enabled?('jrc_relationship'),
                        customer_master: @context.account.feature_enabled?('jrc_customer_master') } }
    @context.account.jrc_crm_sales_orders.find_each do |order|
      report[:scanned] += 1
      eligibility = JrcRelationship::Eligibility.new(order)
      reason = eligibility.reason
      if reason
        report[:excluded][reason] += 1
        report[:excluded_orders] << { order_id: order.id, order_number: order.order_number, status: order.status, reason: reason,
                                     contact_id: order.contact_id, owner_id: order.owner_id, business_unit_id: order.business_unit_id }
        next
      end
      report[:eligible] += 1
      existing = JrcRelationship::Assignment.find_by(eligibility.identity.merge(account: @context.account))
      report[:existing] += 1 if existing
      assignment = apply ? JrcRelationship::Handoff.call(order, actor: @context.user) : existing
      report[:created] += 1 if apply && !existing && assignment
      owner_id = assignment&.owner_id || order.owner_id
      member = @context.account.account_users.find_by(user_id: owner_id)
      owner_access = member && JrcRelationship::ModulePolicy.new({ account: @context.account, account_user: member, user: member.user }, @context.account).manage?
      report[:orders] << { order_id: order.id, order_number: order.order_number, identity: eligibility.identity,
                          status: order.status, active_contracts: order.contracts.where(status: %w[active expiring]).count,
                          signed_contracts: order.contracts.where(signature_status: 'signed').count,
                          assignment_id: assignment&.id, owner_id: owner_id, owner_can_operate_cs: !!owner_access,
                          business_unit_id: order.business_unit_id, already_assigned: existing.present? }
    end
    report[:authorized_assignments_after] = @context.assignments.count
    report
  end
end
