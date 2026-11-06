class JrcRelationship::WorkflowReferences
  COMMERCIAL_MODELS = [JrcRelationship::SuccessPlan, JrcRelationship::ExpansionSignal, JrcRelationship::Qbr].freeze
  GOAL_SOURCES = { 'task_id' => :project_tasks, 'activity_id' => :activities, 'ticket_id' => :tickets }.freeze

  def initialize(context)
    @context = context
    @changed_work_owner_ids = []
  end

  def validate!(record)
    validate_commercial!(record) if COMMERCIAL_MODELS.any? { |model| record.is_a?(model) }
    validate_plan!(record) if record.is_a?(JrcRelationship::SuccessPlan)
    validate_qbr!(record) if record.is_a?(JrcRelationship::Qbr)
    validate_expansion!(record) if record.is_a?(JrcRelationship::ExpansionSignal)
    record.assignment.customer_context(@context.member).contracts.find(record.contract_id) if record.is_a?(JrcRelationship::Renewal)
  end

  def authorize_work_owners!(record)
    return if @changed_work_owner_ids.empty?

    ownership = JrcRelationship::WorkOwnership.new(@context, record.assignment)
    @changed_work_owner_ids.uniq.each { |id| ownership.authorize_record!(record, user_id: id) }
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
    validate_goals!(record, record.goals, record.attribute_in_database('goals'))
    validate_goals!(record, record.metadata['milestones'], record.attribute_in_database('metadata').to_h['milestones'])
    return unless record.project_id

    project = JrcOperations::Access.projects(@context.member).find(record.project_id)
    return if record.assignment.customer_context(@context.member).projects.exists?(id: project.id)

    raise ArgumentError, 'Project must belong to this customer'
  end

  def validate_goals!(record, goals, previous)
    previous = Array(previous)
    Array(goals).each_with_index { |goal, index| validate_goal!(record, goal, previous[index]) }
  end

  def validate_goal!(record, goal, original)
    validate_work_owner!(record, goal, original)
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
    validate_decision_owners!(record)
    Array(record.participants).each { |participant| @context.assignable_users.find(participant['user_id']) if participant['user_id'].present? }
  end

  def validate_decision_owners!(record)
    previous = Array(record.attribute_in_database('decisions')).each_with_index.to_h do |decision, index|
      [decision.fetch('decision_key', index.to_s).to_s, decision]
    end
    Array(record.decisions).each_with_index do |decision, index|
      original = previous[decision.fetch('decision_key', index.to_s).to_s]
      validate_work_owner!(record, decision, original)
    end
  end

  def validate_work_owner!(record, decision, original)
    return if decision['owner_id'].blank?

    @context.assignable_users.find(decision['owner_id'])
    return if original && original['owner_id'].to_s == decision['owner_id'].to_s

    candidate = JrcRelationship::WorkOwnership.new(@context, record.assignment).authorize!(decision['owner_id'])
    @changed_work_owner_ids << candidate.user.id
  end

  def validate_expansion!(record)
    return unless record.product_id

    raise Pundit::NotAuthorizedError unless JrcOperations::Access.crm?(@context.member)

    @context.account.jrc_crm_products.find(record.product_id)
  end
end
