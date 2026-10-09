class JrcRelationship::WorkflowReferences
  COMMERCIAL_MODELS = [JrcRelationship::SuccessPlan, JrcRelationship::ExpansionSignal, JrcRelationship::Qbr].freeze
  GOAL_SOURCES = { 'task_id' => :project_tasks, 'activity_id' => :activities, 'ticket_id' => :tickets }.freeze

  def initialize(context)
    @context = context
  end

  def validate!(record)
    validate_commercial!(record) if COMMERCIAL_MODELS.any? { |model| record.is_a?(model) }
    validate_plan!(record) if record.is_a?(JrcRelationship::SuccessPlan)
    validate_qbr!(record) if record.is_a?(JrcRelationship::Qbr)
    validate_expansion!(record) if record.is_a?(JrcRelationship::ExpansionSignal)
    record.assignment.customer_context(@context.member).contracts.find(record.contract_id) if record.is_a?(JrcRelationship::Renewal)
  end

  private

  def validate_commercial!(record)
    expansion = record.is_a?(JrcRelationship::ExpansionSignal)
    contract = expansion ? record.source_contract : record.contract
    product = expansion ? record.source_product : record.product
    customer = record.assignment.customer_context(@context.member)
    if contract
      customer.contracts.find(contract.id)
      validate_contract_product!(contract, product)
    end
    raise Pundit::NotAuthorizedError if product && !JrcOperations::Access.crm?(@context.member)
  end

  def validate_contract_product!(contract, product)
    return unless product
    return if contract.contract_items.exists?(product_id: product.id) || contract.sales_order.order_items.exists?(product_id: product.id)

    raise ArgumentError, 'Product must belong to the selected contract'
  end

  def validate_plan!(record)
    (Array(record.goals) + Array(record.metadata['milestones'])).each { |goal| validate_goal!(record, goal) }
    return unless record.project_id

    project = JrcOperations::Access.projects(@context.member).find(record.project_id)
    return if record.assignment.customer_context(@context.member).projects.exists?(id: project.id)

    raise ArgumentError, 'Project must belong to this customer'
  end

  def validate_goal!(record, goal)
    @context.assignable_users.find(goal['owner_id']) if goal['owner_id'].present?
    customer = record.assignment.customer_context(@context.member)
    GOAL_SOURCES.each { |key, method| customer.public_send(method).find(goal[key]) if goal[key].present? }
    @context.records(JrcRelationship::Qbr).where(assignment: record.assignment).find(goal['qbr_id']) if goal['qbr_id'].present?
    validate_goal_product!(goal)
  end

  def validate_goal_product!(goal)
    return if goal['product_id'].blank?

    raise Pundit::NotAuthorizedError unless JrcOperations::Access.crm?(@context.member)

    @context.account.jrc_crm_products.find(goal['product_id'])
  end

  def validate_qbr!(record)
    record.assignment.customer_context(@context.member).contacts.find(record.contact_id) if record.contact_id
    Array(record.decisions).each { |decision| @context.assignable_users.find(decision['owner_id']) if decision['owner_id'].present? }
    Array(record.participants).each { |participant| @context.assignable_users.find(participant['user_id']) if participant['user_id'].present? }
  end

  def validate_expansion!(record)
    return unless record.product_id

    raise Pundit::NotAuthorizedError unless JrcOperations::Access.crm?(@context.member)

    @context.account.jrc_crm_products.find(record.product_id)
  end
end
