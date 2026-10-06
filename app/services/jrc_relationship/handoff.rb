class JrcRelationship::Handoff
  def self.call(record)
    account = record.account
    return unless account.feature_enabled?('jrc_relationship') && account.feature_enabled?('jrc_customer_master')
    order = record.is_a?(JrcCrm::SalesOrder) ? record : record.try(:sales_order)
    if order
      return unless JrcCrm::OrderWorkflowSyncService::QUALIFYING_STATUSES.include?(order.status)
      return if JrcCrm::OrderContractService.new(order: order).required? && !order.contracts.where(signature_status: 'signed').exists?
      project_ids = order.backoffice_requests.where(request_kind: 'fulfillment').pluck(Arel.sql("metadata ->> 'implementation_project_id'")).compact
      return if JrcProjects::Project.where(account: account, id: project_ids).where.not(status: 'completed').exists?
    end
    config = JrcRelationship::Configuration.find_by(account: account, scope_key: 'account') || JrcRelationship::Configuration.new(account: account)
    return unless config.effective_rules['auto_handoff']
    contact = record.try(:contact) || record.try(:requester)
    return unless contact
    identity = contact.company_id ? { company_id: contact.company_id } : { contact_id: contact.id }
    assignment = JrcRelationship::Assignment.create_or_find_by!(identity.merge(account: account)) do |row|
      row.owner_id = record.try(:owner_id)
      row.business_unit_id = record.try(:business_unit_id)
      row.status = 'active'
    end
    assignment.with_lock do
      key = 'handoff'
      action = assignment.actions.find_or_initialize_by(source_key: key)
      if action.new_record?
        action.assign_attributes(account: account, owner: assignment.owner, kind: 'onboarding', reason: 'Boas-vindas após implantação',
          due_at: 1.day.from_now, metadata: { source_type: record.class.name, source_id: record.id })
        action.save!
        JrcCustomers::Audit.record!(account: account, actor: nil, resource: assignment, event_type: 'relationship_updated', metadata: { action: 'handoff', source_type: record.class.name, source_id: record.id })
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
