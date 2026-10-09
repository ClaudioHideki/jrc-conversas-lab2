class JrcRelationship::Handoff
  def self.call(record, actor: nil)
    account = record.account
    return unless account.feature_enabled?('jrc_relationship') && account.feature_enabled?('jrc_customer_master')

    order = source_order(record)
    return unless order

    identity = JrcRelationship::Eligibility.new(order).identity
    existing = JrcRelationship::Assignment.find_by(identity.merge(account: account))
    return if JrcRelationship::Eligibility.new(order, exception: existing&.settings&.dig('eligibility_exception')).reason

    rules = JrcRelationship::Configuration.find_by(account: account, scope_key: 'account')&.effective_rules ||
            JrcRelationship::Configuration::DEFAULT_RULES
    assignment = JrcRelationship::Assignment.create_or_find_by!(identity.merge(account: account)) do |row|
      row.owner_id = order.owner_id
      row.business_unit_id = order.business_unit_id
      row.team_id = order.deal&.team_id
      row.status = rules['handoff_acceptance_required'] ? 'onboarding' : 'active'
    end
    assignment.with_lock do
      next unless acceptance_ready?(assignment, order, rules)

      action = welcome_action(assignment, record, actor)
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

  def self.source_order(record)
    return project_order(record) if record.is_a?(JrcProjects::Project)

    record.is_a?(JrcCrm::SalesOrder) ? record : record.try(:sales_order)
  end

  def self.project_order(record)
    account = record.account
    request = account.jrc_crm_backoffice_requests.where(request_kind: 'fulfillment')
                     .find_by("metadata ->> 'implementation_project_id' = ?", record.id.to_s)
    return request.sales_order if request&.sales_order
    return unless record.idempotency_key.to_s.match?(/\Acrm-order-implementation-\d+\z/)

    account.jrc_crm_sales_orders.find_by(id: record.idempotency_key.split('-').last)
  end

  def self.acceptance_ready?(assignment, order, rules)
    return true unless rules['handoff_acceptance_required']

    handoff = JrcRelationship::HandoffCase.create_or_find_by!(
      account: assignment.account, source_type: order.class.name, source_id: order.id
    ) do |row|
      row.assignment = assignment
    end
    return false unless handoff.assignment_id == assignment.id && handoff.status == 'accepted'

    assignment.update!(status: 'active') if assignment.status == 'onboarding'
    true
  end

  def self.welcome_action(assignment, record, actor)
    action = assignment.actions.find_or_initialize_by(source_key: 'handoff')
    return action if action.persisted?

    action.assign_attributes(account: record.account, owner: assignment.owner, kind: 'onboarding', reason: 'Boas-vindas após implantação',
                             due_at: 1.day.from_now, metadata: { source_type: record.class.name, source_id: record.id })
    action.save!
    JrcCustomers::Audit.record!(
      account: record.account, actor: actor, resource: assignment, event_type: 'relationship_updated',
      metadata: { action: 'handoff', source_type: record.class.name, source_id: record.id }
    )
    action
  end

  private_class_method :source_order, :project_order, :acceptance_ready?, :welcome_action
end
