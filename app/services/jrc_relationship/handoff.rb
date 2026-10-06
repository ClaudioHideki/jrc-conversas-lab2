class JrcRelationship::Handoff
  def self.call(record, actor: nil)
    account = record.account
    return unless account.feature_enabled?('jrc_relationship') && account.feature_enabled?('jrc_customer_master')
    order = record.is_a?(JrcCrm::SalesOrder) ? record : record.try(:sales_order)
    if record.is_a?(JrcProjects::Project)
      request = account.jrc_crm_backoffice_requests.where(request_kind: 'fulfillment')
        .find_by("metadata ->> 'implementation_project_id' = ?", record.id.to_s)
      order = request&.sales_order
      if !order && record.idempotency_key.to_s.match?(/\Acrm-order-implementation-\d+\z/)
        order = account.jrc_crm_sales_orders.find_by(id: record.idempotency_key.split('-').last)
      end
    end
    return unless order && !JrcRelationship::Eligibility.new(order).reason
    identity = JrcRelationship::Eligibility.new(order).identity
    assignment = JrcRelationship::Assignment.create_or_find_by!(identity.merge(account: account)) do |row|
      row.owner_id = order.owner_id
      row.business_unit_id = order.business_unit_id
      row.team_id = order.deal&.team_id
      row.status = 'active'
    end
    assignment.with_lock do
      key = 'handoff'
      action = assignment.actions.find_or_initialize_by(source_key: key)
      if action.new_record?
        action.assign_attributes(account: account, owner: assignment.owner, kind: 'onboarding', reason: 'Boas-vindas após implantação',
          due_at: 1.day.from_now, metadata: { source_type: record.class.name, source_id: record.id })
        action.save!
        JrcCustomers::Audit.record!(account: account, actor: actor, resource: assignment, event_type: 'relationship_updated', metadata: { action: 'handoff', source_type: record.class.name, source_id: record.id })
      end
      member = account.account_users.find_by(user_id: assignment.owner_id)
      if member && JrcRelationship::ModulePolicy.new({ account: account, account_user: member, user: member.user }, account).manage?
        context = JrcRelationship::Context.new(member)
        JrcRelationship::OperationalRouting.new(context).prepare!(action) unless action.operations_queue
        action.save!
        JrcRelationship::Workflow.new(context).project_action!(action, kind: 'meeting')
        JrcRelationship::Playbooks.new(context).run!(assignment, 'onboarded')
        JrcRelationship::RefreshJob.perform_later(member.id, [assignment.id])
      end
    end
    assignment
  end
end
